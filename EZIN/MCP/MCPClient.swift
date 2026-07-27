import Foundation

enum MCPError: Error, LocalizedError {
    case badURL, insecureURL, http(Int), rpc(String), parse
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid MCP server URL"
        case .insecureURL: return "MCP servers must use HTTPS, except localhost development servers"
        case .http(let status): return "MCP server returned HTTP \(status)"
        case .rpc(let m): return m
        case .parse: return "Could not parse MCP response"
        }
    }
}

/// Minimal JSON-RPC 2.0 MCP client over streamable HTTP. Best-effort — works with
/// stateless HTTP MCP servers (MT5, TradingView, custom). Handles JSON and SSE replies.
struct MCPClient {
    let connector: MCPConnector

    func listTools() async throws -> [String] {
        try await initialize()
        let r = try await rpc("tools/list", [:])
        let tools = r["tools"] as? [[String: Any]] ?? []
        return tools.compactMap { $0["name"] as? String }
    }

    func callTool(_ name: String, args: [String: Any]) async throws -> String {
        try await initialize()
        let r = try await rpc("tools/call", ["name": name, "arguments": args])
        if let content = r["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return String(describing: r)
    }

    private func initialize() async throws {
        let result = try await rpc("initialize", [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "EZIN", "version": "1.7.0"] as [String: Any]
        ])
        guard result["protocolVersion"] != nil || result["serverInfo"] != nil else {
            throw MCPError.parse
        }
        try await sendInitializedNotification()
    }

    private func sendInitializedNotification() async throws {
        guard let url = URL(string: connector.url),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              ["http", "https"].contains(scheme) else { throw MCPError.badURL }
        if scheme == "http" && host != "localhost" && host != "127.0.0.1" && host != "::1" {
            throw MCPError.insecureURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in connector.headersDict { request.setValue(value, forHTTPHeaderField: key) }
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [String: Any]()
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MCPError.http(http.statusCode)
        }
    }

    private func rpc(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: connector.url),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              ["http", "https"].contains(scheme) else { throw MCPError.badURL }
        if scheme == "http" && host != "localhost" && host != "127.0.0.1" && host != "::1" {
            throw MCPError.insecureURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in connector.headersDict { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 45
        let body: [String: Any] = ["jsonrpc": "2.0", "id": Int.random(in: 1...999999), "method": method, "params": params]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MCPError.http(http.statusCode)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any] { throw MCPError.rpc(err["message"] as? String ?? "MCP error") }
            return obj["result"] as? [String: Any] ?? obj
        }
        // SSE fallback: parse the last data: line as JSON.
        if let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n").reversed() where line.hasPrefix("data:") {
                let js = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let d = js.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    if let err = obj["error"] as? [String: Any] { throw MCPError.rpc(err["message"] as? String ?? "MCP error") }
                    if let r = obj["result"] as? [String: Any] { return r }
                }
            }
        }
        throw MCPError.parse
    }
}
