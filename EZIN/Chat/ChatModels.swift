import Foundation
import Combine

/// One conversational turn passed to a provider.
typealias ChatTurn = (role: String, content: String)

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String       // "user" | "assistant" | "tool"
    var text: String
    var date = Date()
}

struct ChatConfig: Codable {
    var systemPrompt: String = ChatConfig.defaultPrompt
    var autoRoute: Bool = true
    var allowTrading: Bool = false
    var temperature: Double = 0.4

    static let defaultPrompt = """
    You are EZIN Assistant, an expert trading AI inside the EZIN app. You analyse markets, explain \
    signals and indicators, manage trades, and can help with anything else.

    FORMATTING — always reply in clean, professional Markdown:
    - Use ## and ### headings to organise your answer into sections.
    - Use "- " bullet points and numbered lists for factors and steps.
    - Bold key values and verdicts with **double asterisks**. Never leave stray or unmatched asterisks.
    - Keep paragraphs short; prefer clear structure over walls of text.

    ANALYSIS:
    - For ANY request to analyse an instrument, ALWAYS call the analyze tool. It runs a full top-down \
    multi-timeframe study (D1 → H4 → H1 → M15 → M5 → M1): it determines higher-timeframe bias, grades \
    timeframe alignment, lists confluences and returns a structured report with entry/stop/target. \
    Present that report — never analyse from a single timeframe or from memory alone.

    TOOLS — to call one, reply with ONLY this single line and nothing else:
    ACTION: {"tool":"<name>","args":{...}}
    Tools: analyze(symbol,timeframe) · signals() · price(symbol) · instruments(query) · history() · \
    place_trade(symbol,direction[,stake]) · mcp(server,tool,args).
    After a TOOL_RESULT arrives you may call another tool or write the final answer.
    Only place trades when the user explicitly asks and trading is permitted.
    """
}

final class ChatConfigStore: ObservableObject {
    static let shared = ChatConfigStore()
    @Published var config: ChatConfig { didSet { save() } }
    // v2: professional-Markdown + mandatory multi-timeframe analysis defaults.
    private let key = "chat.config.v2"
    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode(ChatConfig.self, from: d) { config = c }
        else { config = ChatConfig() }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(config) { UserDefaults.standard.set(d, forKey: key) }
    }
}
