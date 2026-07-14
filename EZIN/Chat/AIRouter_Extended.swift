import Foundation

/// Extended AI Router with support for Nvidia NIM, FreeModel.dev, and Cerebras
extension AIRouter {
    
    /// Get the API endpoint and model name for new providers
    static func extendedEndpoint(_ p: CredentialKey) -> (url: String, model: String)? {
        switch p {
        case .nvidianim:
            return ("https://integrate.api.nvidia.com/v1/chat/completions", "meta/llama-3.1-405b-instruct")
        case .freemodel:
            return ("https://api.freemodel.dev/v1/chat/completions", "gpt-3.5-turbo")
        case .cerebras:
            return ("https://api.cerebras.ai/v1/chat/completions", "cerebras-7b")
        default:
            return nil
        }
    }
    
    /// Call new provider APIs using OpenAI-compatible format
    static func callExtendedProvider(_ provider: CredentialKey, key: String, system: String, messages: [ChatTurn]) async throws -> String {
        guard let (urlStr, model) = extendedEndpoint(provider) else {
            throw AIProviderError.http("Unsupported provider")
        }
        
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages {
            msgs.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content])
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": msgs,
            "temperature": ChatConfigStore.shared.config.temperature,
            "max_tokens": 1200
        ]
        
        let obj = try await postJSON(urlStr, headers: ["Authorization": "Bearer \(key)"], body: body)
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let msg = first["message"] as? [String: Any], let content = msg["content"] as? String else {
            throw AIProviderError.parse
        }
        return content
    }
    
    /// Helper to post JSON (duplicated from AIRouter for extension compatibility)
    private static func postJSON(_ urlStr: String, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: urlStr) else { throw AIProviderError.http("bad url") }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIProviderError.http("HTTP \(http.statusCode): \(msg.prefix(160))")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.parse
        }
        return obj
    }
}
