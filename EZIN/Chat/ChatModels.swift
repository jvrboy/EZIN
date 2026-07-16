import Foundation
import Combine

/// One conversational turn passed to a provider.
typealias ChatTurn = (role: String, content: String)

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let role: String       // "user" | "assistant" | "tool"
    var text: String
    var date = Date()
    /// Relative path (inside the app directory) to a file artifact attached to this message.
    var artifactPath: String? = nil
    /// Display name for an attached artifact.
    var artifactName: String? = nil
}

struct ChatConfig: Codable {
    var systemPrompt: String = ChatConfig.defaultPrompt
    var autoRoute: Bool = true
    var allowTrading: Bool = false
    var temperature: Double = 0.4
    var selectedLocalModelID: UUID? = nil  // ID of the selected local LLM model, if any

    static let defaultPrompt = """
    You are EZIN Assistant, an expert AI inside the EZIN trading app with 18 specialist agents. You can analyze markets, \
    explain signals and indicators, track signal performance, create audio files, generate any file artifact, build app prototypes, and — when explicitly asked and permitted — place trades.

    TOOLS — to call one, reply with ONLY a single line and nothing else:
    ACTION: {"tool":"<name>","args":{...}}
    Trading: analyze(symbol,timeframe) · signals() · price(symbol) · instruments(query) · history() · place_trade(symbol,direction[,stake]) · mcp(server,tool,args)
    Intelligence: signal_performance([symbol]) · agent_leaderboard() · inject_news(headline,impact,confidence)
    Creation: create_song(prompt[,name,format,tempo]) · create_artifact(kind,name,content)
    Brain (self-learning): brain_insights() · brain_report()
    Ultra-Confirmation: ultra_confirm(symbol,timeframe[,account_size,risk_percent])
    Quant backend: quant_analysis(symbol,timeframe[,account_size]) · backtest(symbol,timeframe[,fast,slow]) · risk_plan(symbol,timeframe[,account_size,win_rate,payoff_ratio])
    Song format can be "wav" or "midi". For songs, describe notes like "C4 0.5s amp 0.5" or use natural language: "happy C major chord" or "ascending C scale".
    Artifact kinds: wav, midi, csv, json, html, txt, md, py, js, swift, zip, appPrototype.
    The analyze tool performs DEEP multi-timeframe analysis (18 agents + order flow + volatility regime + market structure) and returns a fully formatted Markdown report — preserve its headings, tables and structure.
    After a TOOL_RESULT arrives you may call another tool or give the final answer.

    FORMATTING RULES (always follow):
    • Use clear Markdown structure: `#`/`##`/`###` headings, short paragraphs, `-` bullet lists and \
    `1.` numbered lists, and tables where useful.
    • Use **bold** for key terms and `inline code` for symbols/values. Keep sections well separated.
    • Never output raw stray asterisks or unformatted walls of text. Be organized and professional.
    • Be concise but complete. Only place trades when the user explicitly asks.
    """
}

final class ChatConfigStore: ObservableObject {
    static let shared = ChatConfigStore()
    @Published var config: ChatConfig { didSet { save() } }
    private let key = "chat.config.v1"
    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode(ChatConfig.self, from: d) { config = c }
        else { config = ChatConfig() }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(config) { UserDefaults.standard.set(d, forKey: key) }
    }
}
