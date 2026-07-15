import Foundation

// MARK: - Market direction & strength (ported from core/types.py)

enum Direction: Int, Codable {
    case strongBearish = -2
    case bearish = -1
    case neutral = 0
    case bullish = 1
    case strongBullish = 2

    var isBullish: Bool { self == .bullish || self == .strongBullish }
    var isBearish: Bool { self == .bearish || self == .strongBearish }
}

enum SignalStrength: Int, Codable {
    case weak = 1, moderate, strong, veryStrong, extreme
}

enum SignalType: String, Codable {
    case buy = "BUY", sell = "SELL", hold = "HOLD"
    case strongBuy = "STRONG_BUY", strongSell = "STRONG_SELL"

    var isBullish: Bool { self == .buy || self == .strongBuy }
    var isBearish: Bool { self == .sell || self == .strongSell }
    var direction: Direction {
        switch self {
        case .strongBuy: return .strongBullish
        case .buy: return .bullish
        case .strongSell: return .strongBearish
        case .sell: return .bearish
        case .hold: return .neutral
        }
    }
}

enum AssetClass: String, Codable, CaseIterable {
    case forex, crypto, synthetic, commodity, index
}

enum Timeframe: String, Codable, CaseIterable {
    case m1 = "1m", m5 = "5m", m15 = "15m", m30 = "30m", h1 = "1h", h4 = "4h", d1 = "1d"
    /// Deriv granularity in seconds.
    var granularity: Int {
        switch self {
        case .m1: return 60; case .m5: return 300; case .m15: return 900
        case .m30: return 1800; case .h1: return 3600; case .h4: return 14400; case .d1: return 86400
        }
    }
}

// MARK: - OHLCV candle (ported from OHLCV dataclass)

struct Candle: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var body: Double { abs(close - open) }
    var range: Double { high - low }
    var isBullish: Bool { close > open }
    var isBearish: Bool { close < open }
}

// MARK: - MarketData (ported from MarketData dataclass)

struct MarketData {
    let symbol: String
    let assetClass: AssetClass
    let timeframe: Timeframe
    var candles: [Candle]
    var currentPrice: Double = 0
    var bid: Double = 0
    var ask: Double = 0

    var closes: [Double] { candles.map { $0.close } }
    var highs: [Double]  { candles.map { $0.high } }
    var lows: [Double]   { candles.map { $0.low } }
    var opens: [Double]  { candles.map { $0.open } }
    var volumes: [Double] { candles.map { $0.volume } }
    var latest: Candle? { candles.last }
}

// MARK: - Agent vote & council decision (ported from AgentVote / CouncilDecision)

struct AgentVote {
    let agentName: String
    let direction: Direction
    let confidence: Double   // 0...1
    let weight: Double       // agent trust weight
    let rationale: String
}

struct CouncilDecision {
    let symbol: String
    let timeframe: Timeframe
    let direction: Direction
    let confidence: Double
    let consensusRatio: Double
    let votes: [AgentVote]
    let strength: SignalStrength
}
