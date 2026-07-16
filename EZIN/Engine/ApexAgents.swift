import Foundation

// MARK: - APEX council agents
// Second-generation specialist agents. Each one wraps an APEX backend engine so the
// VotingCouncil / MetaOrchestrator automatically gains its confluence — no UI needed.

/// Candlestick pattern agent — votes with recent high-value price-action patterns.
struct PatternAgent: SignalAgent {
    let name = "Patterns"
    let role = "Candlestick Patterns"
    let weight = 0.95
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        let recent = ApexBackend.candlePatterns(md).suffix(6)
        guard !recent.isEmpty else { return vote(name, weight, 0, 0.4, "no patterns") }
        let bull = recent.filter { $0.bullish }.map { $0.strength }.reduce(0, +)
        let bear = recent.filter { !$0.bullish }.map { $0.strength }.reduce(0, +)
        let s = (bull - bear) * 1.4
        let conf = min(0.5 + (bull + bear) * 0.12, 0.85)
        let names = recent.suffix(2).map { $0.name }.joined(separator: ", ")
        return vote(name, weight, s, conf, names)
    }
}

/// Market profile agent — price acceptance above/below the value area.
struct MarketProfileAgent: SignalAgent {
    let name = "Profile"
    let role = "Value Area / POC"
    let weight = 0.85
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        guard let p = ApexBackend.marketProfile(md) else {
            return vote(name, weight, 0, 0.3, "insufficient data")
        }
        let price = md.currentPrice > 0 ? md.currentPrice : (md.closes.last ?? 0)
        var s = 0.0
        if price > p.valueAreaHigh { s += 0.9 }
        else if price < p.valueAreaLow { s -= 0.9 }
        else { s += price > p.pointOfControl ? 0.25 : -0.25 }
        return vote(name, weight, s, 0.6, p.positionLabel)
    }
}

/// Trend quality agent — Kaufman efficiency ratio + entropy; rewards clean trends,
/// punishes chop (where mean-reversion agents should dominate instead).
struct TrendQualityAgent: SignalAgent {
    let name = "TrendQuality"
    let role = "Efficiency Ratio / Entropy"
    let weight = 0.8
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        guard let e = ApexBackend.entropyAnalysis(md.closes) else {
            return vote(name, weight, 0, 0.3, "insufficient data")
        }
        let n = min(20, md.closes.count - 1)
        let drift = (md.closes.last ?? 0) > md.closes[md.closes.count - 1 - n] ? 1.0 : -1.0
        let s = drift * e.efficiencyRatio * 2.2
        let conf = min(0.45 + e.efficiencyRatio * 0.4, 0.85)
        return vote(name, weight, s, conf, "ER \(String(format: "%.2f", e.efficiencyRatio)) · FD \(String(format: "%.2f", e.fractalDimension))")
    }
}

/// Liquidity agent — stop-hunt sweeps and resting-pool gravity.
struct LiquidityAgent: SignalAgent {
    let name = "Liquidity"
    let role = "Sweeps / Equal Highs-Lows"
    let weight = 1.0
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        let m = ApexBackend.liquidityMap(md)
        if m.sweptBelow { return vote(name, weight, 1.3, 0.72, "sell-side sweep → fade up") }
        if m.sweptAbove { return vote(name, weight, -1.3, 0.72, "buy-side sweep → fade down") }
        let price = md.currentPrice > 0 ? md.currentPrice : (md.closes.last ?? 0)
        if let above = m.nearestPoolAbove, let below = m.nearestPoolBelow, price > 0 {
            // Price gravitates toward the nearest resting pool.
            let s = (above - price) < (price - below) ? 0.35 : -0.35
            return vote(name, weight, s, 0.5, "pool gravity \(s > 0 ? "up" : "down")")
        }
        return vote(name, weight, 0, 0.4, "no pools nearby")
    }
}

/// Regime switch agent — Markov-smoothed bull/bear/range probabilities.
struct RegimeSwitchAgent: SignalAgent {
    let name = "RegimeSwitch"
    let role = "Markov Regime Probabilities"
    let weight = 0.9
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        guard let r = ApexBackend.regimeSwitch(md.closes) else {
            return vote(name, weight, 0, 0.3, "insufficient data")
        }
        let s = (r.bull - r.bear) * 2.0
        let conf = min(0.4 + r.persistence * 0.45, 0.85)
        return vote(name, weight, s, conf, "\(r.dominant) · \(Int(r.persistence * 100))% sticky")
    }
}

/// Tape speed agent — signed velocity of the live price series.
struct TapeSpeedAgent: SignalAgent {
    let name = "TapeSpeed"
    let role = "Tick Velocity / Acceleration"
    let weight = 0.7
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        guard let sp = ApexBackend.tickSpeed(md.closes, perSeconds: 60) else {
            return vote(name, weight, 0, 0.3, "insufficient data")
        }
        let s = max(-2, min(2, sp.velocity / 5))
        let conf = min(0.45 + abs(sp.velocity) / 20, 0.8)
        return vote(name, weight, s, conf, sp.reading)
    }
}
