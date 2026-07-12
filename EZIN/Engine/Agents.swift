import Foundation

/// Base agent contract — each agent analyzes market data and casts a weighted vote.
/// (Port of agents/signal_agents.BaseAgent + AgentFactory.)
protocol SignalAgent {
    var name: String { get }
    var role: String { get }
    var weight: Double { get }
    var isActive: Bool { get set }
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote
}

private func vote(_ name: String, _ w: Double, _ score: Double, _ conf: Double, _ why: String) -> AgentVote {
    let dir: Direction
    switch score {
    case let s where s >= 1.5: dir = .strongBullish
    case let s where s > 0.15: dir = .bullish
    case let s where s <= -1.5: dir = .strongBearish
    case let s where s < -0.15: dir = .bearish
    default: dir = .neutral
    }
    return AgentVote(agentName: name, direction: dir, confidence: min(max(conf, 0), 1), weight: w, rationale: why)
}

/// Trend agent — EMA stack + Supertrend + ADX.
struct TrendAgent: SignalAgent {
    let name = "Trend"; let role = "EMA / Supertrend / ADX"; let weight = 1.2; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        if ind.ema12 > ind.ema26 { s += 1 } else { s -= 1 }
        if ind.ema50 > ind.ema200 { s += 0.6 } else { s -= 0.6 }
        if ind.supertrendUp { s += 0.8 } else { s -= 0.8 }
        let conf = min(0.5 + ind.adx / 100, 0.95)
        return vote(name, weight, s, conf, "ADX \(Int(ind.adx)) · ST \(ind.supertrendUp ? "up" : "down")")
    }
}

/// Momentum agent — RSI + MACD + ROC.
struct MomentumAgent: SignalAgent {
    let name = "Momentum"; let role = "RSI / MACD / ROC"; let weight = 1.0; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        if ind.rsi14 > 55 { s += 0.7 } else if ind.rsi14 < 45 { s -= 0.7 }
        if ind.macdHistogram > 0 { s += 0.8 } else { s -= 0.8 }
        if ind.roc12 > 0 { s += 0.4 } else { s -= 0.4 }
        let conf = min(0.55 + abs(ind.rsi14 - 50) / 100, 0.95)
        return vote(name, weight, s, conf, "RSI \(Int(ind.rsi14)) · MACD \(ind.macdHistogram > 0 ? "+" : "-")")
    }
}

/// Mean-reversion agent — Bollinger + Stochastic + Williams %R.
struct MeanReversionAgent: SignalAgent {
    let name = "MeanReversion"; let role = "Bollinger / Stoch / W%R"; let weight = 0.8; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        if ind.bbPosition < 0.1 { s += 1 } else if ind.bbPosition > 0.9 { s -= 1 }
        if ind.stochK < 20 { s += 0.6 } else if ind.stochK > 80 { s -= 0.6 }
        if ind.williamsR < -80 { s += 0.5 } else if ind.williamsR > -20 { s -= 0.5 }
        return vote(name, weight, s, 0.7, "BB pos \(String(format: "%.2f", ind.bbPosition))")
    }
}

/// Volume agent — OBV slope + MFI.
struct VolumeAgent: SignalAgent {
    let name = "Volume"; let role = "OBV / MFI"; let weight = 0.7; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        if ind.mfi14 > 55 { s += 0.7 } else if ind.mfi14 < 45 { s -= 0.7 }
        let obv = Indicators.obv(md.closes, md.volumes)
        if obv.count > 2, obv[obv.count - 1] > obv[obv.count - 2] { s += 0.5 } else { s -= 0.5 }
        return vote(name, weight, s, 0.65, "MFI \(Int(ind.mfi14))")
    }
}

/// Divergence agent — RSI divergence via DivergenceEngine.
struct DivergenceAgent: SignalAgent {
    let name = "Divergence"; let role = "RSI Divergence"; let weight = 1.1; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        let rsi = Indicators.rsi(md.closes, 14)
        let divs = DivergenceEngine.detect(price: md.closes, indicator: rsi)
        guard let latest = divs.max(by: { $0.at < $1.at }) else {
            return vote(name, weight, 0, 0.5, "no divergence")
        }
        let s = latest.type.isBullish ? 1.4 : -1.4
        return vote(name, weight, s, 0.8, latest.type.rawValue)
    }
}

/// Volatility agent — ATR/Bollinger width regime + spike detection.
struct VolatilityAgent: SignalAgent {
    let name = "Volatility"; let role = "ATR / Spike"; let weight = 0.6; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        let spikes = Spike.price(open: md.opens, high: md.highs, low: md.lows, close: md.closes)
        var s = 0.0; var why = "calm"
        if let last = spikes.last, last.spike { s = last.up ? 0.9 : -0.9; why = "spike \(last.up ? "up" : "down")" }
        return vote(name, weight, s, 0.6, why)
    }
}

/// Structure agent — pivot / market structure bias from CCI + ADX DI.
struct StructureAgent: SignalAgent {
    let name = "Structure"; let role = "CCI / DMI"; let weight = 0.9; var isActive = true
    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        if ind.cci20 > 100 { s += 0.8 } else if ind.cci20 < -100 { s -= 0.8 }
        if ind.adxPlusDI > ind.adxMinusDI { s += 0.5 } else { s -= 0.5 }
        return vote(name, weight, s, 0.68, "CCI \(Int(ind.cci20))")
    }
}

enum AgentFactory {
    static func standardCouncil() -> [SignalAgent] {
        [TrendAgent(), MomentumAgent(), MeanReversionAgent(),
         VolumeAgent(), DivergenceAgent(), VolatilityAgent(), StructureAgent()]
    }
}
