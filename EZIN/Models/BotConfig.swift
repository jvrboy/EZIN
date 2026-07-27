import Foundation
import Combine

/// How the bot places protective stops.
enum StopMode: String, Codable, CaseIterable, Identifiable {
    case points  = "Points"
    case pips    = "Pips"
    case profit  = "Profit ($)"
    case botChoice = "Bot Choice"
    var id: String { rawValue }
}

/// Execution mode is deliberately paper-first. Live trading must be explicitly armed
/// in the Bot screen after the user has reviewed the risk settings.
enum TradingExecutionMode: String, Codable, CaseIterable, Identifiable {
    case paper = "Paper Trading"
    case live = "Live Deriv"
    var id: String { rawValue }
}

/// User-configurable settings for the paper-first signal bot.
struct BotConfig: Codable {
    /// Fixed stake per trade (Deriv Multipliers "lot size").
    var fixedLotSize: Double = 1.0
    /// Multiplier leverage for Deriv Multiplier contracts.
    var multiplier: Int = 100
    /// Symbols the bot is allowed to trade (Deriv symbol codes).
    var instruments: [String] = Array(DerivSymbols.volatility.prefix(3) + DerivSymbols.boom.prefix(1) + DerivSymbols.crash.prefix(1) + DerivSymbols.forex.prefix(3) + DerivSymbols.crypto.prefix(2) + DerivSymbols.commodity.prefix(1))
    /// Maximum simultaneously-open positions.
    var maxOpenPositions: Int = 3
    /// Stop configuration.
    var stopMode: StopMode = .botChoice
    /// Value used for points / pips / profit modes.
    var stopLossValue: Double = 50
    var takeProfitValue: Double = 100
    /// Minimum council confidence (0-1) required to fire a trade.
    var minConfidence: Double = 0.7
    /// Account currency.
    var currency: String = "USD"

    // Safety controls.
    var executionMode: TradingExecutionMode = .paper
    var dailyTradeLimit: Int = 10
    var dailyLossLimit: Double = 0
    var stalePriceSeconds: Double = 20
    var requireOrderPreview: Bool = true

    static let storageKey = "botConfig.v2"

    private enum CodingKeys: String, CodingKey {
        case fixedLotSize, multiplier, instruments, maxOpenPositions, stopMode,
             stopLossValue, takeProfitValue, minConfidence, currency,
             executionMode, dailyTradeLimit, dailyLossLimit, stalePriceSeconds,
             requireOrderPreview
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fixedLotSize = try c.decodeIfPresent(Double.self, forKey: .fixedLotSize) ?? 1.0
        multiplier = try c.decodeIfPresent(Int.self, forKey: .multiplier) ?? 100
        instruments = try c.decodeIfPresent([String].self, forKey: .instruments) ?? Array(DerivSymbols.volatility.prefix(3))
        maxOpenPositions = try c.decodeIfPresent(Int.self, forKey: .maxOpenPositions) ?? 3
        stopMode = try c.decodeIfPresent(StopMode.self, forKey: .stopMode) ?? .botChoice
        stopLossValue = try c.decodeIfPresent(Double.self, forKey: .stopLossValue) ?? 50
        takeProfitValue = try c.decodeIfPresent(Double.self, forKey: .takeProfitValue) ?? 100
        minConfidence = try c.decodeIfPresent(Double.self, forKey: .minConfidence) ?? 0.7
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        executionMode = try c.decodeIfPresent(TradingExecutionMode.self, forKey: .executionMode) ?? .paper
        dailyTradeLimit = try c.decodeIfPresent(Int.self, forKey: .dailyTradeLimit) ?? 10
        dailyLossLimit = try c.decodeIfPresent(Double.self, forKey: .dailyLossLimit) ?? 0
        stalePriceSeconds = try c.decodeIfPresent(Double.self, forKey: .stalePriceSeconds) ?? 20
        requireOrderPreview = try c.decodeIfPresent(Bool.self, forKey: .requireOrderPreview) ?? true
    }
}

/// Persisted bot configuration store.
final class BotConfigStore: ObservableObject {
    static let shared = BotConfigStore()
    @Published var config: BotConfig { didSet { save() } }
    private let d = UserDefaults.standard

    private init() {
        if let data = d.data(forKey: BotConfig.storageKey),
           let cfg = try? JSONDecoder().decode(BotConfig.self, from: data) {
            config = cfg
        } else if let legacy = d.data(forKey: "botConfig.v1"),
                  let cfg = try? JSONDecoder().decode(BotConfig.self, from: legacy) {
            config = cfg
        } else {
            config = BotConfig()
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(config) { d.set(data, forKey: BotConfig.storageKey) }
    }
}
