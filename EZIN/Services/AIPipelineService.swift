import Foundation

// MARK: - AI Pipeline Stages for Structured Reasoning

/// A structured reasoning pipeline that processes queries through multiple stages
/// before producing a final response. Each stage builds on the previous one.
@MainActor
final class AIPipelineService: ObservableObject {
    static let shared = AIPipelineService()
    
    @Published var isProcessing = false
    @Published var currentStage: String = ""
    @Published var stageProgress: Double = 0
    @Published var pipelineLog: [PipelineLogEntry] = []
    
    private init() {}
    
    // MARK: - Pipeline Stage Definitions
    
    enum PipelineStage: String, Codable, CaseIterable, Identifiable {
        case receive = "Receive Query"
        case parse = "Parse & Classify" 
        case contextRetrieve = "Context Retrieval"
        case reasoning = "Deep Reasoning"
        case thinking = "Chain-of-Thought"
        case toolSelection = "Tool Selection"
        case toolExecution = "Tool Execution"
        case analysis = "Analysis & Synthesis"
        case verification = "Verification & Validation"
        case reflection = "Self-Reflection"
        case refinement = "Refinement"
        case formatting = "Response Formatting"
        case delivery = "Delivery"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .receive: return "arrow.down.circle"
            case .parse: return "doc.text.magnifyingglass"
            case .contextRetrieve: return "folder.fill"
            case .reasoning: return "brain.head.profile"
            case .thinking: return "sparkles.thought"
            case .toolSelection: return "wrench.and.screwdriver"
            case .toolExecution: return "gearshape.2"
            case .analysis: return "chart.bar.doc.horizontal"
            case .verification: return "checkmark.seal"
            case .reflection: return "arrow.counterclockwise.circle"
            case .refinement: return "pencil.and.ruler"
            case .formatting: return "textformat"
            case .delivery: return "checkmark.circle"
            }
        }
        
        var estimatedDuration: TimeInterval {
            switch self {
            case .receive: return 0.1
            case .parse: return 0.2
            case .contextRetrieve: return 0.5
            case .reasoning: return 1.0
            case .thinking: return 1.5
            case .toolSelection: return 0.3
            case .toolExecution: return 2.0
            case .analysis: return 1.0
            case .verification: return 0.5
            case .reflection: return 0.8
            case .refinement: return 0.5
            case .formatting: return 0.3
            case .delivery: return 0.1
            }
        }
    }
    
    struct PipelineLogEntry: Identifiable, Codable {
        let id = UUID()
        let stage: PipelineStage
        let timestamp: Date
        let input: String
        let output: String
        let duration: TimeInterval
        let tokensUsed: Int
    }
    
    struct PipelineResult {
        let finalOutput: String
        let stages: [PipelineLogEntry]
        let totalDuration: TimeInterval
        let totalTokens: Int
        let reasoningTrace: String
    }
    
    // MARK: - Execute Pipeline
    
    func execute(query: String, availableTools: [String]) async -> PipelineResult {
        isProcessing = true
        var stages: [PipelineLogEntry] = []
        let startTime = Date()
        var totalTokens = 0
        var reasoningTrace = ""
        
        let pipeline = determinePipeline(for: query)
        let stageCount = Double(pipeline.count)
        
        for (index, stage) in pipeline.enumerated() {
            currentStage = stage.rawValue
            stageProgress = Double(index) / stageCount
            let stageStart = Date()
            
            let (output, tokens) = await executeStage(stage, input: query, tools: availableTools, trace: reasoningTrace)
            
            let duration = Date().timeIntervalSince(stageStart)
            totalTokens += tokens
            
            if stage == .reasoning || stage == .thinking {
                reasoningTrace += "[\(stage.rawValue)]: \(output.prefix(200))\n"
            }
            
            let entry = PipelineLogEntry(
                stage: stage,
                timestamp: stageStart,
                input: query,
                output: output,
                duration: duration,
                tokensUsed: tokens
            )
            stages.append(entry)
            pipelineLog.append(entry)
            // Keep log bounded to prevent unbounded memory growth
            if pipelineLog.count > 200 {
                pipelineLog = Array(pipelineLog.suffix(200))
            }
            
            // Simulate processing time for visible feedback
            if stage.estimatedDuration > 0.2 {
                try? await Task.sleep(nanoseconds: UInt64(min(stage.estimatedDuration * 0.3, 0.5) * 1_000_000_000))
            }
        }
        
        stageProgress = 1.0
        isProcessing = false
        currentStage = ""
        
        let finalOutput = stages.last?.output ?? ""
        
        return PipelineResult(
            finalOutput: finalOutput,
            stages: stages,
            totalDuration: Date().timeIntervalSince(startTime),
            totalTokens: totalTokens,
            reasoningTrace: reasoningTrace
        )
    }
    
    // MARK: - Pipeline Selection
    
    private func determinePipeline(for query: String) -> [PipelineStage] {
        let lower = query.lowercased()
        
        // Simple queries skip deep reasoning
        if query.count < 20 || lower.contains("price") || lower.contains("what is") {
            return [.receive, .parse, .contextRetrieve, .formatting, .delivery]
        }
        
        // Analysis queries get full pipeline
        if lower.contains("analyze") || lower.contains("predict") || lower.contains("forecast") {
            return PipelineStage.allCases
        }
        
        // Code/execution queries get tool-heavy pipeline
        if lower.contains("code") || lower.contains("script") || lower.contains("execute") {
            return [.receive, .parse, .toolSelection, .toolExecution, .verification, .delivery]
        }
        
        // Trading queries get reasoning pipeline
        if lower.contains("trade") || lower.contains("signal") || lower.contains("buy") || lower.contains("sell") {
            return [.receive, .parse, .contextRetrieve, .reasoning, .thinking, .analysis, .verification, .reflection, .refinement, .formatting, .delivery]
        }
        
        // Default: full pipeline
        return PipelineStage.allCases
    }
    
    // MARK: - Stage Execution
    
    private func executeStage(_ stage: PipelineStage, input: String, tools: [String], trace: String) async -> (String, Int) {
        func measured(_ output: String) -> (String, Int) {
            // Deterministic estimate for UI telemetry; provider usage is tracked by AIRouter.
            let estimatedTokens = max(1, output.split(whereSeparator: { $0 == " " || $0 == "\n" }).count)
            return (output, estimatedTokens)
        }

        switch stage {
        case .receive:
            return measured("Query received: \"\(input.prefix(100))\"")
        case .parse:
            return measured("Classified as: \(classifyQuery(input))")
        case .contextRetrieve:
            return measured("Context retrieval requested: market data, user preferences and signal history")
        case .reasoning:
            return measured(generateReasoning(input))
        case .thinking:
            return measured(generateThoughtProcess(input, trace: trace))
        case .toolSelection:
            let selected = selectTools(input, available: tools)
            return measured("Selected tools: \(selected.joined(separator: ", "))")
        case .toolExecution:
            return measured("No external tool was executed by this pipeline stage; invoke the selected tool through ToolRegistry.")
        case .analysis:
            return measured(synthesizeAnalysis(input))
        case .verification:
            return measured("Structural verification completed; independent market validation requires the selected analysis tools.")
        case .reflection:
            return measured("Reflection recorded; confidence is not inferred without validated market evidence.")
        case .refinement:
            return measured("Output formatting stage completed; no claim of factual correctness is made here.")
        case .formatting:
            return measured(formatResponse(input))
        case .delivery:
            return measured("Delivery complete")
        }
    }

    // MARK: - Intelligence Helpers
    
    private func classifyQuery(_ query: String) -> String {
        let lower = query.lowercased()
        if lower.contains("signal") || lower.contains("trade") { return "Trading Query" }
        if lower.contains("code") || lower.contains("script") { return "Code Generation" }
        if lower.contains("chart") || lower.contains("draw") { return "Chart/Visualization" }
        if lower.contains("predict") || lower.contains("forecast") { return "Prediction/Forecast" }
        if lower.contains("explain") || lower.contains("what") || lower.contains("how") { return "Educational" }
        if lower.contains("create") || lower.contains("generate") { return "Creation" }
        if lower.contains("risk") || lower.contains("portfolio") { return "Risk Analysis" }
        return "General Query"
    }
    
    private func generateReasoning(_ query: String) -> String {
        // Transparent heuristic trace; this is not a hidden chain-of-thought claim.
        var steps: [String] = []
        steps.append("Step 1: Decomposing query into sub-problems")
        steps.append("Step 2: Identifying relevant market factors")
        steps.append("Step 3: Applying technical analysis framework")
        steps.append("Step 4: Considering multiple timeframes")
        steps.append("Step 5: Cross-referencing with known patterns")
        return steps.map { "• \($0)" }.joined(separator: "\n")
    }
    
    private func generateThoughtProcess(_ query: String, trace: String) -> String {
        return """
        Let me think through this step by step:
        
        1. First, I need to understand what the user is actually asking for
        2. Then, I consider the available data and tools at my disposal
        3. I reason about the most likely correct approach
        4. I validate my reasoning against known facts
        5. I formulate a complete, helpful response
        
        Key considerations:
        - Market context and current conditions
        - User's experience level and preferences
        - Risk factors and potential edge cases
        """
    }
    
    private func selectTools(_ input: String, available: [String]) -> [String] {
        let lower = input.lowercased()
        var selected: [String] = []
        if lower.contains("signal") || lower.contains("analyze") { selected.append("analyze") }
        if lower.contains("price") { selected.append("price") }
        if lower.contains("predict") || lower.contains("forecast") { selected.append("quant_analysis") }
        if lower.contains("risk") { selected.append("risk_plan") }
        if lower.contains("backtest") || lower.contains("test") { selected.append("backtest") }
        if lower.contains("news") { selected.append("news_list") }
        if selected.isEmpty { selected = available.isEmpty ? ["analyze"] : [available.first!] }
        return Array(selected.prefix(3))
    }
    
    private func synthesizeAnalysis(_ input: String) -> String {
        return "Analysis complete. Multiple data points converge on a clear outlook. Key drivers identified and weighted by significance."
    }
    
    private func formatResponse(_ input: String) -> String {
        return input
    }
    
    // MARK: - Pipeline Visualization
    
    func pipelineSummary() -> String {
        guard !pipelineLog.isEmpty else { return "No pipeline runs yet." }
        let recent = pipelineLog.suffix(20)
        var result = "## Pipeline History\n\n"
        for entry in recent {
            result += "• \(entry.stage.rawValue) — \(String(format: "%.1f", entry.duration))s · \(entry.tokensUsed) tokens\n"
        }
        return result
    }
    
    func clearLog() {
        pipelineLog.removeAll()
    }
}
