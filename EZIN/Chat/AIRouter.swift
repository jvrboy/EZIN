import Foundation

enum AIProviderError: Error, LocalizedError {
    case noKey, http(String), parse
    var errorDescription: String? {
        switch self {
        case .noKey: return "No AI API keys configured. Add one in Settings → AI API Keys."
        case .http(let m): return m
        case .parse: return "Could not parse the AI response."
        }
    }
}

/// Auto-routing AI client: picks the most powerful available provider and falls back on failure.
/// Uses APIKeyStore round-robin so multiple keys per provider are all used.
enum AIRouter {
    /// Most-powerful-first priority order.
    static let priority: [CredentialKey] = [.openAI, .anthropic, .openRouter, .gemini, .groq, .mistral, .huggingFace]

    static func availableProviders() -> [CredentialKey] {
        priority.filter { APIKeyStore.shared.count(for: $0) > 0 }
    }

    static func complete(system: String, messages: [ChatTurn], preferred: CredentialKey? = nil) async -> Result<String, Error> {
        var order = availableProviders()
        if let p = preferred, order.contains(p) { order.removeAll { $0 == p }; order.insert(p, at: 0) }
        guard !order.isEmpty else { return .failure(AIProviderError.noKey) }
        for provider in order {
            guard let key = APIKeyStore.shared.next(for: provider) else { continue }
            do {
                let text = try await call(provider, key: key, system: system, messages: messages)
                if !text.isEmpty { return .success(text) }
            } catch { continue }
        }
        return .failure(AIProviderError.http("All available providers failed or are rate-limited."))
    }

    // MARK: - Providers

    private static func call(_ provider: CredentialKey, key: String, system: String, messages: [ChatTurn]) async throws -> String {
        switch provider {
        case .anthropic: return try await callAnthropic(key: key, system: system, messages: messages)
        case .gemini: return try await callGemini(key: key, system: system, messages: messages)
        case .huggingFace: throw AIProviderError.noKey
        default: return try await callOpenAICompatible(provider, key: key, system: system, messages: messages)
        }
    }

    private static func endpoint(_ p: CredentialKey) -> (url: String, model: String) {
        switch p {
        case .openAI: return ("https://api.openai.com/v1/chat/completions", "gpt-4o")
        case .groq: return ("https://api.groq.com/openai/v1/chat/completions", "llama-3.3-70b-versatile")
        case .mistral: return ("https://api.mistral.ai/v1/chat/completions", "mistral-large-latest")
        case .openRouter: return ("https://openrouter.ai/api/v1/chat/completions", "openai/gpt-4o")
        default: return ("https://api.openai.com/v1/chat/completions", "gpt-4o")
        }
    }

    private static func callOpenAICompatible(_ provider: CredentialKey, key: String, system: String, messages: [ChatTurn]) async throws -> String {
        let (urlStr, model) = endpoint(provider)
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages { msgs.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content]) }
        let body: [String: Any] = ["model": model, "messages": msgs, "temperature": ChatConfigStore.shared.config.temperature]
        let obj = try await postJSON(urlStr, headers: ["Authorization": "Bearer \(key)"], body: body)
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let msg = first["message"] as? [String: Any], let content = msg["content"] as? String else { throw AIProviderError.parse }
        return content
    }

    private static func callAnthropic(key: String, system: String, messages: [ChatTurn]) async throws -> String {
        var msgs: [[String: Any]] = []
        for m in messages { msgs.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content]) }
        let body: [String: Any] = ["model": "claude-3-5-sonnet-latest", "max_tokens": 1200, "system": system, "messages": msgs]
        let obj = try await postJSON("https://api.anthropic.com/v1/messages",
                                     headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: body)
        guard let content = obj["content"] as? [[String: Any]] else { throw AIProviderError.parse }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    private static func callGemini(key: String, system: String, messages: [ChatTurn]) async throws -> String {
        var contents: [[String: Any]] = []
        for m in messages { contents.append(["role": m.role == "assistant" ? "model" : "user", "parts": [["text": m.content]]]) }
        let body: [String: Any] = ["contents": contents, "systemInstruction": ["parts": [["text": system]]]]
        let obj = try await postJSON("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=\(key)",
                                     headers: [:], body: body)
        guard let cands = obj["candidates"] as? [[String: Any]], let c0 = cands.first,
              let cont = c0["content"] as? [String: Any], let parts = cont["parts"] as? [[String: Any]] else { throw AIProviderError.parse }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: - Transport

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
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIProviderError.parse }
        return obj
    }
}
