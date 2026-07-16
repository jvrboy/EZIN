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
        let modelPath = documentsURL.appendingPathComponent("Models").appendingPathComponent(model.relativePath).path
        
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
        
        // Simulate inference with a realistic delay (in production, this would call llama.cpp bindings)
        // For now, we'll return a placeholder response to demonstrate the architecture.
        let startTime = Date()
        var result = ""
        
        // Simulate token-by-token generation
        let simulatedTokens = generateSimulatedResponse(for: prompt, maxTokens: config.maxTokens)
        for token in simulatedTokens {
            if Task.isCancelled {
                throw LocalLLMError.cancelled
            }
            
            // Simulate processing time per token
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms per token
            result += token
            onToken?(token)
        }
        
        self.lastInferenceTime = Date()
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
    
    /// Simulate a response for demonstration purposes.
    /// In production, this would be replaced with actual llama.cpp inference.
    private func generateSimulatedResponse(for prompt: String, maxTokens: Int) -> [String] {
        let responses: [String: [String]] = [
            "price": ["The", " current", " price", " is", " based", " on", " market", " dynamics", "."],
            "signal": ["A", " strong", " buy", " signal", " has", " been", " detected", " based", " on", " technical", " indicators", "."],
            "analysis": ["The", " market", " shows", " bullish", " momentum", " with", " strong", " volume", " support", "."],
        ]
        
        let lowerPrompt = prompt.lowercased()
        for (key, tokens) in responses {
            if lowerPrompt.contains(key) {
                return Array(tokens.prefix(maxTokens))
            }
        }
        
        // Default response
        return Array(["The", " analysis", " is", " complete", "."].prefix(maxTokens))
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
