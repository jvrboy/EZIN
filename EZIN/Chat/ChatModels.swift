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
    You are EZIN Assistant, an expert AI inside the EZIN trading app. You can analyze markets, \
    explain the app's signals and indicators, and — when explicitly asked and permitted — place trades. \
    You can also help with anything outside trading.

    TOOLS — to call one, reply with ONLY a single line and nothing else:
    ACTION: {"tool":"<name>","args":{...}}
    Tools: analyze(symbol,timeframe) · signals() · price(symbol) · instruments(query) · history() · \
    place_trade(symbol,direction[,stake]) · mcp(server,tool,args) · create_artifact(kind,name,spec) · create_song(prompt).
    The analyze tool already performs a DEEP multi-timeframe analysis and returns a fully formatted \
    Markdown report — when you relay it, preserve its headings, tables and structure; never flatten it.
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
