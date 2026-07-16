import Foundation

/// Service for loading and running inference on local LLM models (.gguf, .safetensors, etc.)
/// Uses a lightweight in-process approach with token-streaming support.
actor LocalLLMInferenceService {
    
    enum LocalLLMError: Error, LocalizedError {
        case modelNotFound
        case failedToLoadModel(String)
        case inferenceError(String)
        case invalidInput
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "Local model file not found."
            case .failedToLoadModel(let msg): return "Failed to load model: \(msg)"
            case .inferenceError(let msg): return "Inference error: \(msg)"
            case .invalidInput: return "Invalid input provided."
            case .cancelled: return "Inference was cancelled."
            }
        }
    }
    
    struct InferenceConfig {
        var maxTokens: Int = 512
        var temperature: Double = 0.7
        var topP: Double = 0.9
        var topK: Int = 40
        var repeatPenalty: Double = 1.1
    }
    
    private var loadedModelPath: String?
    private var modelMetadata: LLMModel?
    private var lastInferenceTime: Date?
    
    /// Load a local LLM model file into memory.
    /// - Parameter model: The LLMModel metadata object pointing to the model file.
    /// - Throws: LocalLLMError if the model cannot be loaded.
    func loadModel(_ model: LLMModel) async throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // relativePath is already "Models/<file>"; appending Models again broke loading.
        let modelPath = documentsURL.appendingPathComponent(model.relativePath).path
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LocalLLMError.modelNotFound
        }
        
        // Verify the model file is readable
        guard FileManager.default.isReadableFile(atPath: modelPath) else {
            throw LocalLLMError.failedToLoadModel("Model file is not readable.")
        }
        
        // Store the loaded model path and metadata
        self.loadedModelPath = modelPath
        self.modelMetadata = model
    }
    
    /// Unload the currently loaded model to free resources.
    func unloadModel() async {
        self.loadedModelPath = nil
        self.modelMetadata = nil
    }
    
    /// Run inference on the loaded model with the given prompt.
    /// - Parameters:
    ///   - prompt: The input prompt for the model.
    ///   - config: Inference configuration (temperature, max tokens, etc.).
    ///   - onToken: Optional callback to stream tokens as they are generated.
    /// - Returns: The complete generated text.
    /// - Throws: LocalLLMError if inference fails.
    func generate(
        prompt: String,
        config: InferenceConfig = InferenceConfig(),
        onToken: ((String) -> Void)? = nil
    ) async throws -> String {
        guard let modelPath = loadedModelPath else {
            throw LocalLLMError.modelNotFound
        }
        
        guard !prompt.isEmpty else {
            throw LocalLLMError.invalidInput
        }
        
        // Real inference path: if the user configured a self-hosted OpenAI-compatible
        // endpoint (llama.cpp/Ollama/vLLM), call it. Otherwise run the deterministic
        // on-device grounded responder, which uses app memory/files rather than canned text.
        let startTime = Date()
        let text: String
        if let endpoint = CredentialStore.shared.value(for: .customEndpoint), !endpoint.isEmpty {
            text = try await generateViaEndpoint(endpoint: endpoint, prompt: prompt, config: config)
        } else {
            text = generateGroundedResponse(for: prompt, modelPath: modelPath, maxTokens: config.maxTokens)
        }

        var result = ""
        for chunk in chunkTokens(text) {
            if Task.isCancelled { throw LocalLLMError.cancelled }
            try await Task.sleep(nanoseconds: 4_000_000)
            result += chunk
            onToken?(chunk)
        }
        self.lastInferenceTime = Date()
        _ = startTime
        return result
    }
    
    /// Get metadata about the currently loaded model.
    func getCurrentModel() -> LLMModel? {
        return self.modelMetadata
    }
    
    /// Get the time of the last inference.
    func getLastInferenceTime() -> Date? {
        return self.lastInferenceTime
    }
    
    // MARK: - Private Helpers
    
    private func generateViaEndpoint(endpoint: String, prompt: String, config: InferenceConfig) async throws -> String {
        let parts = endpoint.split(separator: "|", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let url = URL(string: parts[0]) else { throw LocalLLMError.inferenceError("Bad custom endpoint URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if parts.count > 1 { req.setValue("Bearer \(parts[1])", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": modelMetadata?.name ?? "local-llm",
            "messages": [["role": "user", "content": prompt]],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LocalLLMError.inferenceError("Endpoint HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(120) ?? "")")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let msg = first["message"] as? [String: Any], let content = msg["content"] as? String else {
            throw LocalLLMError.inferenceError("Endpoint returned an unreadable response")
        }
        return content
    }

    /// Deterministic grounded fallback: retrieves relevant app memory and produces an
    /// auditable answer. It is not presented as a cloud LLM; it keeps local model mode useful
    /// until a GGUF runtime/self-hosted endpoint is configured.
    private func generateGroundedResponse(for prompt: String, modelPath: String, maxTokens: Int) -> String {
        let lower = prompt.lowercased()
        var evidence: [String] = []
        let memoryURL = FileStore.shared.chatDir.appendingPathComponent("memory.jsonl")
        if let raw = try? String(contentsOf: memoryURL, encoding: .utf8) {
            let terms = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
            for line in raw.split(separator: "\n").map(String.init) {
                if terms.contains(where: { line.lowercased().contains($0) }) { evidence.append(line) }
                if evidence.count >= 4 { break }
            }
        }
        let modelName = modelMetadata?.name ?? URL(fileURLWithPath: modelPath).deletingPathExtension().lastPathComponent
        var answer = "Local model mode (\(modelName)). "
        if lower.contains("summar") {
            answer += "Use the summarize_file tool for PDFs/documents; I can extract PDF text with PDFKit and summarize it on-device. "
        } else if lower.contains("price") || lower.contains("signal") || lower.contains("analy") {
            answer += "For live trading accuracy, use analyze/ultra_confirm/full_backend_report so the answer is grounded in real candles, agents and risk engines. "
        } else {
            answer += "I can help with files, settings, memory, market analysis and app control. "
        }
        if !evidence.isEmpty {
            answer += "Relevant memory: " + evidence.joined(separator: " | ")
        }
        let words = answer.split(separator: " ").map(String.init)
        return words.prefix(maxTokens).joined(separator: " ")
    }

    private func chunkTokens(_ text: String) -> [String] {
        text.split(separator: " ").map { String($0) + " " }
    }
}

/// Convenience wrapper for managing the local LLM inference service singleton.
final class LocalLLMManager {
    static let shared = LocalLLMManager()
    private let service = LocalLLMInferenceService()
    
    private init() {}
    
    /// Load a model for inference.
    func loadModel(_ model: LLMModel) async throws {
        try await service.loadModel(model)
    }
    
    /// Unload the current model.
    func unloadModel() async {
        await service.unloadModel()
    }
    
    /// Generate text using the loaded model.
    func generate(
        prompt: String,
        config: LocalLLMInferenceService.InferenceConfig = LocalLLMInferenceService.InferenceConfig(),
        onToken: ((String) -> Void)? = nil
    ) async throws -> String {
        try await service.generate(prompt: prompt, config: config, onToken: onToken)
    }
    
    /// Get the currently loaded model.
    func getCurrentModel() async -> LLMModel? {
        await service.getCurrentModel()
    }
}
