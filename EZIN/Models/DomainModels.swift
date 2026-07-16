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
    case derivToken, customEndpoint, localLLM
    case nvidianim, freemodel, cerebras
    case cloudflareAI, ollamaCloud, kiloCode, sambaNova
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
        case .localLLM: return "Local LLM"
        case .nvidianim: return "Nvidia NIM"
        case .freemodel: return "FreeModel.dev"
        case .cerebras: return "Cerebras"
        case .cloudflareAI: return "Cloudflare Workers AI"
        case .ollamaCloud: return "Ollama Cloud"
        case .kiloCode: return "Kilo Code"
        case .sambaNova: return "Samba Nova Cloud"
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
        case fetchMultiTimeframe = "Fetch Multi-Timeframe Data"
        case computeIndicators = "Compute Indicators"
        case detectDivergence = "Detect Divergence"
        case runAgents = "Run Agents"
        case councilVote = "Council Vote"
        case runSystematic = "Systematic Analysis"
        case runMathScience = "Mathematical/FX Science"
        case runRNG = "RNG & Monte Carlo"
        case runNeural = "On-Device Neural Inference"
        case runChaos = "Chaos Regime Analysis"
        case runBayesian = "Bayesian Update"
        case runFuzzy = "Fuzzy Confluence"
        case runOrderFlow = "Order Flow / Microstructure"
        case runHarmonic = "Harmonic Pattern Scan"
        case runElliott = "Elliott Wave Count"
        case runSessionLiquidity = "Session & Liquidity"
        case runAnomaly = "Anomaly Scan"
        case runRisk = "Risk & Money Management"
        case runBacktest = "Backtest / Walk-Forward"
        case runDocumentIntelligence = "Document Intelligence"
        case runFileTool = "File Tool"
        case runWebScrape = "Web Scrape"
        case runMemoryRecall = "Memory Recall"
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
        Pipeline(name: "Full Backend Confluence Pipeline", stages: [
            .init(kind: .fetchMultiTimeframe),
            .init(kind: .computeIndicators),
            .init(kind: .detectDivergence),
            .init(kind: .runAgents),
            .init(kind: .councilVote),
            .init(kind: .runSystematic),
            .init(kind: .runMathScience),
            .init(kind: .runRNG),
            .init(kind: .runNeural),
            .init(kind: .runChaos),
            .init(kind: .runBayesian),
            .init(kind: .runFuzzy),
            .init(kind: .runOrderFlow),
            .init(kind: .runHarmonic),
            .init(kind: .runElliott),
            .init(kind: .runSessionLiquidity),
            .init(kind: .runAnomaly),
            .init(kind: .runRisk),
            .init(kind: .runBacktest),
            .init(kind: .llmReview),
            .init(kind: .emitSignal),
        ])
    }
}

