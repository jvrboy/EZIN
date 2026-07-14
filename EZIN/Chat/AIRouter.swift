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
/// Prioritizes local LLM models if selected, then falls back to remote providers.
/// Uses APIKeyStore round-robin so multiple keys per provider are all used.
enum AIRouter {
    /// Most-powerful-first priority order for remote providers.
    static let priority: [CredentialKey] = [.openAI, .anthropic, .cerebras, .nvidianim, .openRouter, .gemini, .groq, .mistral, .freemodel, .huggingFace]

    static func availableProviders() -> [CredentialKey] {
        var providers = priority.filter { APIKeyStore.shared.count(for: $0) > 0 }
        // Add local LLM if any models are imported
        if !LLMModelStore.shared.models.isEmpty {
            providers.insert(.localLLM, at: 0)
        }
        return providers
    }

    static func complete(system: String, messages: [ChatTurn], preferred: CredentialKey? = nil) async -> Result<String, Error> {
        // Check if a local LLM model is selected and available
        if let selectedModelID = ChatConfigStore.shared.config.selectedLocalModelID,
           let model = LLMModelStore.shared.models.first(where: { $0.id == selectedModelID }) {
            do {
                // Try local inference first if a model is selected
                try await LocalLLMManager.shared.loadModel(model)
                let prompt = buildPrompt(system: system, messages: messages)
                let text = try await LocalLLMManager.shared.generate(prompt: prompt)
                if !text.isEmpty { return .success(text) }
            } catch {
                // Fall back to remote providers if local inference fails
            }
        }
        
        // Fall back to remote providers
        var order = availableProviders().filter { $0 != .localLLM }
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
        case .nvidianim, .freemodel, .cerebras: return try await callExtendedProvider(provider, key: key, system: system, messages: messages)
        case .huggingFace: throw AIProviderError.noKey
        case .localLLM: throw AIProviderError.noKey
        default: return try await callOpenAICompatible(provider, key: key, system: system, messages: messages)
        }
    }

    private static func endpoint(_ p: CredentialKey) -> (url: String, model: String) {
        switch p {
        case .openAI: return ("https://api.openai.com/v1/chat/completions", "gpt-4o")
        case .groq: return ("https://api.groq.com/openai/v1/chat/completions", "llama-3.3-70b-versatile")
        case .mistral: return ("https://api.mistral.ai/v1/chat/completions", "mistral-large-latest")
        case .openRouter: return ("https://openrouter.ai/api/v1/chat/completions", "openai/gpt-4o")
        case .nvidianim: return ("https://integrate.api.nvidia.com/v1/chat/completions", "meta/llama-3.1-405b-instruct")
        case .freemodel: return ("https://api.freemodel.dev/v1/chat/completions", "gpt-3.5-turbo")
        case .cerebras: return ("https://api.cerebras.ai/v1/chat/completions", "cerebras-7b")
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

    private static func callExtendedProvider(_ provider: CredentialKey, key: String, system: String, messages: [ChatTurn]) async throws -> String {
        let (urlStr, model) = endpoint(provider)
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages { msgs.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content]) }
        let body: [String: Any] = ["model": model, "messages": msgs, "temperature": ChatConfigStore.shared.config.temperature, "max_tokens": 1200]
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

    // MARK: - Helpers

    /// Build a single prompt string from system instruction and message history.
    private static func buildPrompt(system: String, messages: [ChatTurn]) -> String {
        var prompt = "System: \(system)\n\n"
        for msg in messages {
            prompt += "\(msg.role.capitalized): \(msg.content)\n"
        }
        prompt += "Assistant: "
        return prompt
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
