import Foundation
import PDFKit

/// Real on-device document reader/summarizer used by chat tools. Supports PDF text
/// extraction through PDFKit plus UTF-8 text/code/data files. No MCP server is required
/// to read, summarize, create or rename files inside the app container.
enum DocumentIntelligence {

    static func resolveFile(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fm = FileStore.shared.fm
        let direct = FileStore.shared.url(forRelative: trimmed)
        if fm.fileExists(atPath: direct.path) { return direct }

        let roots = [FileStore.shared.artifactsDir, FileStore.shared.projectsDir, FileStore.shared.chatDir, FileStore.shared.dataDir]
        let lower = trimmed.lowercased()
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                if name == lower || name.contains(lower) { return url }
            }
        }
        return nil
    }

    static func extractText(from url: URL, limit: Int = 80_000) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { return "" }
            var text = doc.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var pages: [String] = []
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i), let s = page.string { pages.append(s) }
                }
                text = pages.joined(separator: "\n")
            }
            return String(text.prefix(limit))
        }
        if ["txt", "md", "markdown", "json", "csv", "html", "htm", "swift", "py", "js", "ts", "xml", "log", "yaml", "yml"].contains(ext) {
            return String((try? String(contentsOf: url, encoding: .utf8))?.prefix(limit) ?? "")
        }
        if let data = try? Data(contentsOf: url), let text = String(data: data.prefix(limit), encoding: .utf8) {
            return text
        }
        return ""
    }

    /// Extractive summarizer: scores sentences by informative term frequency and returns
    /// the strongest sentences in original order. Deterministic and offline.
    static func summarize(_ text: String, maxSentences: Int = 8, maxChars: Int = 4_000) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let sentences = splitSentences(cleaned)
        guard sentences.count > maxSentences else { return String(cleaned.prefix(maxChars)) }

        var freq: [String: Int] = [:]
        for sentence in sentences {
            for token in tokens(sentence) { freq[token, default: 0] += 1 }
        }
        let scored: [(index: Int, sentence: String, score: Double)] = sentences.enumerated().map { idx, sentence in
            let toks = tokens(sentence)
            let score = toks.reduce(0.0) { $0 + Double(freq[$1] ?? 0) } / Double(max(toks.count, 1))
            return (idx, sentence, score)
        }
        let chosen = scored.sorted { $0.score > $1.score }.prefix(maxSentences).sorted { $0.index < $1.index }
        var out = chosen.map { "• " + $0.sentence }.joined(separator: "\n")
        if out.count > maxChars { out = String(out.prefix(maxChars)) + "…" }
        return out
    }

    static func summarizeFile(_ query: String, maxSentences: Int = 10) -> String {
        guard let url = resolveFile(query) else {
            return "I couldn't find a file matching '\(query)'. Import it in Chat/Projects or create one with create_file first."
        }
        let text = extractText(from: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "I found \(url.lastPathComponent), but it has no extractable UTF-8/PDF text. If it's scanned, OCR needs to be enabled in a future build."
        }
        let summary = summarize(text, maxSentences: maxSentences)
        return "## \(url.lastPathComponent)\n\n" + summary
    }

    static func filePreview(_ query: String, chars: Int = 2_000) -> String {
        guard let url = resolveFile(query) else { return "No file found for '\(query)'." }
        let text = extractText(from: url, limit: max(chars * 4, 4_000))
        guard !text.isEmpty else { return "No extractable text in \(url.lastPathComponent)." }
        return "## \(url.lastPathComponent)\n\n" + String(text.prefix(chars))
    }

    private static func tokens(_ sentence: String) -> [String] {
        sentence.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.count > 25 { out.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count > 25 { out.append(tail) }
        return out
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "are", "was", "were", "has", "have", "had",
        "not", "but", "you", "your", "about", "into", "over", "under", "then", "than", "they", "them",
        "their", "there", "here", "will", "would", "could", "should", "can", "may", "might", "its", "it's",
        "our", "out", "use", "used", "using", "via", "per", "all", "any", "each", "other", "more", "most"
    ]
}
