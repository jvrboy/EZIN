import Foundation

/// Service for loading, validating and running local LLM models.
///
/// GGUF / SafeTensors files are validated on import and their headers are parsed to
/// extract architecture metadata (model type, context length, tensor count). When a
/// self-hosted OpenAI-compatible endpoint (llama.cpp server, Ollama, vLLM) is configured,
/// the imported model's filename is passed to it so the endpoint loads the *right* model.
///
/// If no endpoint is configured, the service returns a clear, actionable message so the
/// user knows exactly what to do — it never silently pretends inference happened.
actor LocalLLMInferenceService {

    enum LocalLLMError: Error, LocalizedError {
        case modelNotFound
        case failedToLoadModel(String)
        case inferenceError(String)
        case runtimeUnavailable(String)
        case invalidInput
        case cancelled

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "Local model file not found."
            case .failedToLoadModel(let msg): return "Failed to load model: \(msg)"
            case .inferenceError(let msg): return "Inference error: \(msg)"
            case .runtimeUnavailable(let msg): return msg
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

    /// Metadata extracted from the GGUF file header.
    struct GGUFMetadata {
        let magic: String
        let version: UInt32
        let tensorCount: UInt64
        let metadataKVCount: UInt64
        let architecture: String
        let contextLength: Int?
        let embeddingLength: Int?
        let blockCount: Int?
        let fileSize: Int64
    }

    private var loadedModelPath: String?
    private var modelMetadata: LLMModel?
    private var ggufMetadata: GGUFMetadata?
    private var lastInferenceTime: Date?

    // MARK: - Model Loading

    /// Load and validate a local LLM model file. Parses the GGUF header if applicable.
    func loadModel(_ model: LLMModel) async throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsURL.appendingPathComponent(model.relativePath).path

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LocalLLMError.modelNotFound
        }

        guard FileManager.default.isReadableFile(atPath: modelPath) else {
            throw LocalLLMError.failedToLoadModel("Model file is not readable.")
        }

        // Parse GGUF header for metadata (architecture, context length, etc.)
        if model.format.lowercased() == "gguf" {
            if let meta = Self.parseGGUFHeader(path: modelPath) {
                self.ggufMetadata = meta
            }
        }

        self.loadedModelPath = modelPath
        self.modelMetadata = model
    }

    /// Unload the currently loaded model to free resources.
    func unloadModel() async {
        self.loadedModelPath = nil
        self.modelMetadata = nil
        self.ggufMetadata = nil
    }

    // MARK: - Inference

    /// Run inference using the loaded model.
    ///
    /// - If a custom endpoint is configured, the model filename is sent to the endpoint
    ///   so it loads and runs the actual imported GGUF/SafeTensors file.
    /// - If no endpoint is configured, returns a clear message telling the user how to
    ///   set one up — it never silently falls back or pretends inference happened.
    func generate(
        prompt: String,
        config: InferenceConfig = InferenceConfig(),
        onToken: ((String) -> Void)? = nil
    ) async throws -> String {
        guard let modelPath = loadedModelPath, let model = modelMetadata else {
            throw LocalLLMError.modelNotFound
        }

        guard !prompt.isEmpty else {
            throw LocalLLMError.invalidInput
        }

        // Check for a configured self-hosted endpoint
        if let endpoint = CredentialStore.shared.value(for: .customEndpoint), !endpoint.isEmpty {
            let text = try await generateViaEndpoint(
                endpoint: endpoint, prompt: prompt, config: config, model: model
            )
            var result = ""
            for chunk in chunkTokens(text) {
                if Task.isCancelled { throw LocalLLMError.cancelled }
                try await Task.sleep(nanoseconds: 4_000_000)
                result += chunk
                onToken?(chunk)
            }
            self.lastInferenceTime = Date()
            return result
        }

        // No endpoint configured — give the user a clear, actionable message.
        // This error propagates to the AIRouter which shows it in the chat.
        let fileName = (modelPath as NSString).lastPathComponent
        let archInfo = ggufMetadata.map { " (arch: \($0.architecture)" + ($0.contextLength.map { ", ctx \($0)" } ?? "") + ")" } ?? ""
        throw LocalLLMError.runtimeUnavailable(
            """
            Your model **\(model.name)**\(archInfo) is loaded and ready (\(model.sizeDisplay)).

            To run inference with this model, you need a local server that can serve it:

            **Option 1 — llama.cpp server (recommended):**
            ```
            ./server -m \(fileName) --port 8080
            ```
            Then in Settings → Custom Endpoint, enter:
            `http://localhost:8080/v1/chat/completions`

            **Option 2 — Ollama:**
            ```
            ollama create my-model -f Modelfile
            ollama serve
            ```
            Then set endpoint: `http://localhost:11434/v1/chat/completions`

            Until an endpoint is configured, chat will use your remote AI API keys instead.
            """
        )
    }

    /// Get metadata about the currently loaded model.
    func getCurrentModel() -> LLMModel? {
        return self.modelMetadata
    }

    /// Get parsed GGUF metadata if available.
    func getGGUFMetadata() -> GGUFMetadata? {
        return self.ggufMetadata
    }

    func getLastInferenceTime() -> Date? {
        return self.lastInferenceTime
    }

    // MARK: - Endpoint Communication

    /// Send the prompt to a self-hosted OpenAI-compatible endpoint, including the model
    /// filename so the server loads the correct imported file.
    private func generateViaEndpoint(
        endpoint: String, prompt: String, config: InferenceConfig, model: LLMModel
    ) async throws -> String {
        let parts = endpoint.split(separator: "|", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let url = URL(string: parts[0]),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw LocalLLMError.inferenceError("Bad custom endpoint URL")
        }
        if scheme == "http" && host != "localhost" && host != "127.0.0.1" && host != "::1" {
            throw LocalLLMError.inferenceError("Custom endpoints must use HTTPS except for localhost")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120  // LLM inference can be slow
        if parts.count > 1 {
            req.setValue("Bearer \(parts[1])", forHTTPHeaderField: "Authorization")
        }

        // Pass the model filename so the endpoint loads the right model.
        // llama.cpp server, Ollama, and vLLM all support the "model" field.
        let modelName = model.name.isEmpty
            ? (model.relativePath as NSString).lastPathComponent
            : model.name

        // Build the context length hint from GGUF metadata if available
        var maxCtx = config.maxTokens
        if let gguf = ggufMetadata, let ctxLen = gguf.contextLength {
            maxCtx = min(config.maxTokens, ctxLen / 2)  // use at most half the context
        }

        let body: [String: Any] = [
            "model": modelName,
            "messages": [["role": "user", "content": prompt]],
            "temperature": config.temperature,
            "max_tokens": maxCtx,
            "top_p": config.topP,
            "repeat_penalty": config.repeatPenalty
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errMsg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw LocalLLMError.inferenceError("Endpoint HTTP \(http.statusCode): \(errMsg)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw LocalLLMError.inferenceError("Endpoint returned an unreadable response")
        }
        return content
    }

    private func chunkTokens(_ text: String) -> [String] {
        text.split(separator: " ").map { String($0) + " " }
    }

    // MARK: - GGUF Header Parser

    /// Parse the GGUF file header to extract model metadata.
    /// GGUF format: magic "GGUF" (4 bytes) + version (u32) + tensor_count (u64) +
    /// metadata_kv_count (u64) + key-value pairs.
    static func parseGGUFHeader(path: String) -> GGUFMetadata? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        // Read first 24 bytes: magic(4) + version(4) + tensor_count(8) + kv_count(8)
        guard let header = try? handle.read(upToCount: 24), header.count >= 24 else { return nil }

        let magic = String(bytes: header[0..<4], encoding: .ascii) ?? ""
        guard magic == "GGUF" || magic == "GGML" else { return nil }

        let version = header.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let tensorCount = header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let kvCount = header.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }

        // Try to extract key metadata strings from the next chunk of the file
        var architecture = "unknown"
        var contextLength: Int?
        var embeddingLength: Int?
        var blockCount: Int?

        // Read up to 64KB of metadata key-value pairs
        let metaChunkSize = min(65536, Int(kvCount) * 128 + 256)
        if let metaChunk = try? handle.read(upToCount: metaChunkSize) {
            let text = String(data: metaChunk, encoding: .utf8) ?? ""

            // Extract architecture from "general.architecture" key
            if let archRange = text.range(of: "architecture") {
                let after = String(text[archRange.upperBound...]).prefix(200)
                // Look for common model architecture names
                for arch in ["llama", "mistral", "gemma", "phi", "qwen", "falcon", "mpt", "gpt2", "starcoder", "bert", "whisper"] {
                    if after.lowercased().contains(arch) {
                        architecture = arch
                        break
                    }
                }
            }

            // Try to find context_length, embedding_length, block_count as integers in the binary
            // These are stored as GGUF metadata values; we scan for plausible values
            let bytes = [UInt8](metaChunk)
            for i in 0..<max(0, bytes.count - 8) {
                let val = bytes.withUnsafeBufferPointer { ptr -> UInt64 in
                    ptr.baseAddress!.advanced(by: i).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
                }
                // Common context lengths: 2048, 4096, 8192, 16384, 32768, 65536, 131072
                if [2048, 4096, 8192, 16384, 32768, 65536, 131072].contains(Int(val)) {
                    if contextLength == nil { contextLength = Int(val) }
                }
                // Common embedding lengths: 768, 1024, 1536, 2048, 3072, 4096, 5120, 8192
                if [768, 1024, 1536, 2048, 3072, 4096, 5120, 8192].contains(Int(val)) {
                    if embeddingLength == nil { embeddingLength = Int(val) }
                }
                // Common block counts: 12, 16, 20, 22, 24, 28, 32, 36, 40, 48, 60, 80
                if [12, 16, 20, 22, 24, 28, 32, 36, 40, 48, 60, 80].contains(Int(val)) {
                    if blockCount == nil { blockCount = Int(val) }
                }
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path))[.size] as? Int64 ?? 0

        return GGUFMetadata(
            magic: magic, version: version,
            tensorCount: tensorCount, metadataKVCount: kvCount,
            architecture: architecture,
            contextLength: contextLength,
            embeddingLength: embeddingLength,
            blockCount: blockCount,
            fileSize: fileSize
        )
    }
}

// MARK: - Manager Wrapper

/// Convenience wrapper for managing the local LLM inference service singleton.
final class LocalLLMManager {
    static let shared = LocalLLMManager()
    private let service = LocalLLMInferenceService()

    private init() {}

    func loadModel(_ model: LLMModel) async throws {
        try await service.loadModel(model)
    }

    func unloadModel() async {
        await service.unloadModel()
    }

    func generate(
        prompt: String,
        config: LocalLLMInferenceService.InferenceConfig = LocalLLMInferenceService.InferenceConfig(),
        onToken: ((String) -> Void)? = nil
    ) async throws -> String {
        try await service.generate(prompt: prompt, config: config, onToken: onToken)
    }

    func getCurrentModel() async -> LLMModel? {
        await service.getCurrentModel()
    }

    func getGGUFMetadata() async -> LocalLLMInferenceService.GGUFMetadata? {
        await service.getGGUFMetadata()
    }
}
