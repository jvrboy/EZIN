import Foundation

enum MCPError: Error, LocalizedError {
    case badURL, rpc(String), parse
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid MCP server URL"
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
        let r = try await rpc("tools/list", [:])
        let tools = r["tools"] as? [[String: Any]] ?? []
        return tools.compactMap { $0["name"] as? String }
    }

    func callTool(_ name: String, args: [String: Any]) async throws -> String {
        let r = try await rpc("tools/call", ["name": name, "arguments": args])
        if let content = r["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return String(describing: r)
    }

    private func rpc(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: connector.url) else { throw MCPError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in connector.headersDict { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 45
        let body: [String: Any] = ["jsonrpc": "2.0", "id": Int.random(in: 1...999999), "method": method, "params": params]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
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
