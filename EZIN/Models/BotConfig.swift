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

/// User-configurable settings for the perpetual scalper bot.
/// The bot uses ALL strategies/indicators equally (no single default strategy).
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

    static let storageKey = "botConfig.v1"
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
        } else {
            config = BotConfig()
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(config) { d.set(data, forKey: BotConfig.storageKey) }
    }
}
