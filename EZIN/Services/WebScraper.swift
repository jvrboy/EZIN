import Foundation
import Darwin

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection newRequest: URLRequest,
        newResponse response: HTTPURLResponse,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Redirects are followed manually only after the destination passes the same SSRF checks.
        completionHandler(nil)
    }
}

/// A small, defensive web extractor for public text pages.
/// It is not a browser automation engine and does not execute JavaScript.
actor WebScraper {
    static let shared = WebScraper()

    struct Result: Codable, Sendable {
        let requestedURL: String
        let finalURL: String
        let statusCode: Int
        let title: String
        let description: String
        let text: String
        let links: [String]
        let fetchedAt: Date
    }

    enum ScraperError: Error, LocalizedError {
        case invalidURL
        case blockedHost
        case redirectLimit
        case responseTooLarge
        case unsupportedContentType(String)
        case httpStatus(Int)
        case noText

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter a valid public HTTP or HTTPS URL."
            case .blockedHost: return "Private, local, and link-local network addresses cannot be scraped."
            case .redirectLimit: return "The page exceeded the redirect limit."
            case .responseTooLarge: return "The page exceeded the scraper response-size limit."
            case .unsupportedContentType(let value): return "Unsupported web content type: \(value)."
            case .httpStatus(let status): return "The web server returned HTTP \(status)."
            case .noText: return "No readable text was found on the page."
            }
        }
    }

    private let delegate = NoRedirectSessionDelegate()
    private let session: URLSession
    private let maximumBytes = 2 * 1024 * 1024

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func scrape(url rawURL: String, maxCharacters: Int = 20_000) async throws -> Result {
        guard let initialURL = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ScraperError.invalidURL
        }
        let requested = try validatedPublicURL(initialURL)
        let (data, response, finalURL) = try await fetch(requested, redirectsRemaining: 3)
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.isEmpty || contentType.contains("text/html") || contentType.contains("text/plain") || contentType.contains("application/xhtml") else {
            throw ScraperError.unsupportedContentType(contentType)
        }
        guard data.count <= maximumBytes else { throw ScraperError.responseTooLarge }

        let html = decode(data: data, response: response)
        let title = firstCapture(in: html, pattern: "<title[^>]*>(.*?)</title>")
            .map(cleanInlineText) ?? finalURL.host ?? "Untitled page"
        let description = metaDescription(in: html)
        let text = extractText(from: html, limit: max(500, min(maxCharacters, 100_000)))
        guard !text.isEmpty else { throw ScraperError.noText }
        let links = extractLinks(from: html, baseURL: finalURL, limit: 50)

        return Result(
            requestedURL: requested.absoluteString,
            finalURL: finalURL.absoluteString,
            statusCode: response.statusCode,
            title: title,
            description: description,
            text: text,
            links: links,
            fetchedAt: Date()
        )
    }

    private func fetch(_ url: URL, redirectsRemaining: Int) async throws -> (Data, HTTPURLResponse, URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("EZIN/1.0 (+public text scraper)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,text/plain,application/xhtml+xml;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")

        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw ScraperError.invalidURL }
        if let contentLength = response.value(forHTTPHeaderField: "Content-Length"),
           let bytes = Int(contentLength), bytes > maximumBytes {
            throw ScraperError.responseTooLarge
        }

        if (300...399).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location") {
            guard redirectsRemaining > 0 else { throw ScraperError.redirectLimit }
            guard let destination = URL(string: location, relativeTo: url)?.absoluteURL else { throw ScraperError.invalidURL }
            return try await fetch(validatedPublicURL(destination), redirectsRemaining: redirectsRemaining - 1)
        }
        guard (200...299).contains(response.statusCode) else { throw ScraperError.httpStatus(response.statusCode) }
        guard data.count <= maximumBytes else { throw ScraperError.responseTooLarge }
        return (data, response, response.url ?? url)
    }

    private func validatedPublicURL(_ url: URL) throws -> URL {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { throw ScraperError.invalidURL }
        guard !isPrivateHost(host), resolvedAddressesArePublic(host) else { throw ScraperError.blockedHost }
        if let port = url.port, ![80, 443].contains(port) { throw ScraperError.blockedHost }
        return url
    }

    private func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return true
        }
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized == "::1" || normalized == "::" || normalized.hasPrefix("fc") || normalized.hasPrefix("fd") || normalized.hasPrefix("fe80:") {
            return true
        }
        let parts = normalized.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let a = parts[0], b = parts[1]
            return a == 0 || a == 10 || a == 127 ||
                (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) ||
                (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) || a >= 224
        }
        return false
    }

    private func resolvedAddressesArePublic(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }

        var current: UnsafeMutablePointer<addrinfo>? = first
        var foundAddress = false
        while let addressInfo = current {
            let family = addressInfo.pointee.ai_family
            if family == AF_INET || family == AF_INET6,
               let address = addressInfo.pointee.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    address,
                    addressInfo.pointee.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    foundAddress = true
                    let numeric = String(cString: buffer)
                    if isPrivateHost(numeric) { return false }
                }
            }
            current = addressInfo.pointee.ai_next
        }
        return foundAddress
    }

    private func decode(data: Data, response: HTTPURLResponse) -> String {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("charset=iso-8859-1") || contentType.contains("charset=windows-1252") {
            return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func extractText(from html: String, limit: Int) -> String {
        var value = html
        value = replacing(value, pattern: "<!--[\\s\\S]*?-->", with: " ")
        value = replacing(value, pattern: "<(script|style|noscript|svg|template)[^>]*>[\\s\\S]*?</\\1>", with: " ")
        value = replacing(value, pattern: "</?(p|div|section|article|main|header|footer|aside|h[1-6]|li|tr|br|hr)[^>]*>", with: "\n")
        value = replacing(value, pattern: "<[^>]+>", with: " ")
        value = decodeEntities(value)
        value = replacing(value, pattern: "[ \\t]+", with: " ")
        value = replacing(value, pattern: " *\\n *", with: "\n")
        value = replacing(value, pattern: "\\n{3,}", with: "\n\n")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(limit))
    }

    private func extractLinks(from html: String, baseURL: URL, limit: Int) -> [String] {
        let pattern = "<a[^>]+href\\s*=\\s*[\\\"']([^\\\"'#]+)[\\\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>(), result: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard result.count < limit, match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: html),
                  let resolved = URL(string: String(html[capture]), relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(resolved.scheme?.lowercased() ?? "") else { continue }
            let value = resolved.absoluteString
            if seen.insert(value).inserted { result.append(value) }
        }
        return result
    }

    private func metaDescription(in html: String) -> String {
        let patterns = [
            "<meta[^>]+name\\s*=\\s*[\\\"']description[\\\"'][^>]+content\\s*=\\s*[\\\"']([^\\\"']*)[\\\"']",
            "<meta[^>]+content\\s*=\\s*[\\\"']([^\\\"']*)[\\\"'][^>]+name\\s*=\\s*[\\\"']description[\\\"']"
        ]
        for pattern in patterns {
            if let value = firstCapture(in: html, pattern: pattern) { return cleanInlineText(value) }
        }
        return ""
    }

    private func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[capture])
    }

    private func cleanInlineText(_ value: String) -> String {
        replacing(decodeEntities(value), pattern: "\\s+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacing(_ value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return value }
        return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value), withTemplate: replacement)
    }

    private func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
    }
}
