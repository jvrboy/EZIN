import Foundation

// MARK: - Imported LLM model file (.gguf / .safetensors / any)

struct LLMModel: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var fileName: String
    var relativePath: String     // path inside the app's Models directory
    var byteSize: Int64
    var format: String           // gguf, safetensors, bin, ...
    var importedAt: Date

    var sizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

// MARK: - AI API credential providers (saved to local storage / Keychain)

enum CredentialKey: String, Codable, CaseIterable, Identifiable {
    case openAI, anthropic, gemini, groq, mistral, openRouter, huggingFace
    case derivToken, customEndpoint
    var id: String { rawValue }

    var display: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .groq: return "Groq"
        case .mistral: return "Mistral"
        case .openRouter: return "OpenRouter"
        case .huggingFace: return "Hugging Face"
        case .derivToken: return "Deriv API Token"
        case .customEndpoint: return "Custom Endpoint"
        }
    }
    var isAIProvider: Bool { self != .derivToken && self != .customEndpoint }
}

// MARK: - Pipeline (ordered chain of processing stages)

struct PipelineStage: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: Kind
    var enabled: Bool = true

    enum Kind: String, Codable, CaseIterable {
        case fetchMarketData = "Fetch Market Data"
        case computeIndicators = "Compute Indicators"
        case detectDivergence = "Detect Divergence"
        case runAgents = "Run Agents"
        case councilVote = "Council Vote"
        case llmReview = "LLM Review"
        case emitSignal = "Emit Signal"
        case autoTrade = "Auto Trade"
    }
}

struct Pipeline: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var stages: [PipelineStage]
    var enabled: Bool = true

    static var `default`: Pipeline {
        Pipeline(name: "Default Council Pipeline", stages: [
            .init(kind: .fetchMarketData),
            .init(kind: .computeIndicators),
            .init(kind: .detectDivergence),
            .init(kind: .runAgents),
            .init(kind: .councilVote),
            .init(kind: .emitSignal),
        ])
    }
}

// MARK: - Backend bot descriptor (agents run hidden; this is just status metadata)

struct BotDescriptor: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    var active: Bool
    var lastVote: String
}
