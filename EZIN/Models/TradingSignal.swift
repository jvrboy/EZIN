import Foundation

/// A live trading signal surfaced in the Signals tab.
struct TradingSignal: Codable, Identifiable {
    var id = UUID()
    let symbol: String
    let displayPair: String
    let type: SignalType
    let entry: Double
    let stopLoss: Double
    let takeProfit: Double
    var confidence: Double        // 0...100 for display
    let strategy: String
    let timeframe: Timeframe
    let createdAt: Date
    var expiresAt: Date

    var isBuy: Bool { type == .buy || type == .strongBuy }
    var riskReward: Double {
        let risk = abs(entry - stopLoss)
        let reward = abs(takeProfit - entry)
        return risk > 0 ? reward / risk : 0
    }
}

