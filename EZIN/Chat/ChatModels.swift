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
    You are EZIN Assistant, an expert AI inside the EZIN trading app. You can analyze markets, \
    explain the app's signals and indicators, and — when explicitly asked and permitted — place trades. \
    You can also help with anything outside trading.
    You have access to TOOLS. To call one, reply with ONLY a single line and nothing else:
    ACTION: {"tool":"<name>","args":{...}}
    Tools: analyze(symbol,timeframe) · signals() · price(symbol) · instruments(query) · history() · \
    place_trade(symbol,direction[,stake]) · mcp(server,tool,args).
    After a TOOL_RESULT arrives you may call another tool or answer. Give final answers in clear, concise language. \
    Only place trades when the user explicitly asks.
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
