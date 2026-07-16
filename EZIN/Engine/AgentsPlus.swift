import Foundation

// MARK: - Order Flow Agent
/// Analyzes candle-derived order-flow proxies (aggressive volume, trade direction,
/// absorption, delta trend) to determine buyer/seller control.
struct OrderFlowAgent: SignalAgent {
    let name = "OrderFlow"
    let role = "Aggressive Volume / Delta / Absorption"
    let weight = 1.15
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        let flow = Microstructure.orderFlow(
            open: md.opens, high: md.highs, low: md.lows,
            close: md.closes, volume: md.volumes, window: 30
        )

        var s = 0.0
        // Net aggressive volume bias
        s += flow.netAggressiveVolumeProxy * 2.0
        // Trade direction ratio
        if flow.tradeDirectionRatioProxy > 0.6 { s += 0.8 }
        else if flow.tradeDirectionRatioProxy < 0.4 { s -= 0.8 }
        // Delta trend
        s += flow.deltaTrendProxy * 1.5
        // Absorption (high absorption after a move = potential reversal)
        let absScore = max(-1, min(1, flow.absorptionProxy * 0.5))
        s += (flow.netAggressiveVolumeProxy > 0 ? -absScore : absScore)

        let conf = 0.55 + min(abs(flow.netAggressiveVolumeProxy), 0.35)
        let why = "AggVol \(String(format: "%.2f", flow.netAggressiveVolumeProxy)) · " +
                  "DirRatio \(String(format: "%.2f", flow.tradeDirectionRatioProxy)) · " +
                  "Delta \(String(format: "%.3f", flow.deltaTrendProxy))"
        return vote(name, weight, s, conf, why)
    }
}

// MARK: - Volatility Regime Agent
/// Classifies market into calm/normal/high/ultra volatility and adjusts bias
/// accordingly — trend-following works better in normal vol, mean-reversion in extremes.
struct VolatilityRegimeAgent: SignalAgent {
    let name = "VolRegime"
    let role = "Volatility Regime / Speed / Acceleration"
    let weight = 0.95
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        let regime = Microstructure.regime(md.closes)
        let vel = Microstructure.velocity(md.closes, n: 10)

        var s = 0.0
        var why = ""

        switch regime {
        case .calm:
            // In calm markets, follow the gentle drift.
            s += vel.speed > 0 ? 0.3 : -0.3
            why = "Calm · spd \(String(format: "%.3f", vel.speed))"
        case .normal:
            // Normal vol: standard momentum approach.
            s += vel.speed > 0 ? 0.6 : -0.6
            s += vel.accel > 0 ? 0.3 : -0.3
            why = "Normal · spd \(String(format: "%.3f", vel.speed)) · acc \(String(format: "%.3f", vel.accel))"
        case .high:
            // High vol: be cautious, look for exhaustion.
            if abs(vel.speed) > 2.0 && vel.accel < 0 {
                s += vel.speed > 0 ? -0.8 : 0.8  // exhaustion fade
                why = "High-Vol Exhaustion · spd \(String(format: "%.2f", vel.speed))"
            } else {
                s += vel.speed > 0 ? 0.5 : -0.5
                why = "High-Vol · spd \(String(format: "%.2f", vel.speed))"
            }
        case .ultra:
            // Ultra-high: mean-reversion / wait.
            s += vel.speed > 0 ? -1.0 : 1.0
            why = "Ultra · fade spd \(String(format: "%.2f", vel.speed))"
        }

        let conf = 0.5 + min(abs(vel.speed) / 10.0, 0.4)
        return vote(name, weight, s, conf, why)
    }
}

// MARK: - News-Reactive Agent
/// Placeholder framework for news/sentiment-driven signals.
/// When a news feed is connected (via MCP or future integration), this agent
/// will parse event impact and cross-reference with historical volatility reactions.
struct NewsReactiveAgent: SignalAgent {
    let name = "News"
    let role = "Event/Sentiment Impact"
    let weight = 0.9
    var isActive = true

    // In-memory cache of recent "news events" that can be injected by MCP tools.
    static var recentEvents: [NewsEvent] = []

    struct NewsEvent {
        let timestamp: Date
        let impact: Impact // -1 bearish, 0 neutral, 1 bullish
        let confidence: Double
        let headline: String

        enum Impact: Int { case bearish = -1, neutral, bullish }
    }

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        // Filter events from last 15 minutes relevant to this symbol.
        let relevant = Self.recentEvents.filter {
            $0.timestamp > Date().addingTimeInterval(-900)
        }
        guard let latest = relevant.max(by: { $0.confidence < $1.confidence }) else {
            return vote(name, weight, 0, 0.3, "no recent events")
        }
        let s = Double(latest.impact.rawValue) * latest.confidence * 2.0
        let why = "\(latest.headline.prefix(40))… (\(Int(latest.confidence * 100))%)"
        return vote(name, weight, s, latest.confidence, why)
    }

    /// Inject a news event from external source (MCP tool, push notification, etc.)
    static func injectEvent(headline: String, impact: NewsEvent.Impact, confidence: Double) {
        recentEvents.append(NewsEvent(timestamp: Date(), impact: impact, confidence: confidence, headline: headline))
        // Keep only last 50 events.
        if recentEvents.count > 50 { recentEvents.removeFirst(recentEvents.count - 50) }
    }
}

// MARK: - Risk Guardian Agent
/// Monitors portfolio-level risk: correlation concentration, drawdown proximity,
/// volatility-adjusted position sizing cues. Does NOT vote direction directly;
/// instead it modulates confidence of other agents via the MetaOrchestrator.
struct RiskGuardianAgent: SignalAgent {
    let name = "RiskGuard"
    let role = "Portfolio Risk / Drawdown / Correlation"
    let weight = 0.7
    var isActive = true

    // Risk state (updated externally by the trading session).
    static var portfolioDrawdown: Double = 0  // 0..1
    static var dailyLoss: Double = 0
    static var correlationClusterSize: Int = 0
    static var maxDailyLoss: Double = -1000

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        var why = ""

        // If in drawdown, reduce risk appetite → neutral/slight contrarian bias.
        if Self.portfolioDrawdown > 0.05 {
            s -= 0.5
            why += "DD \(Int(Self.portfolioDrawdown * 100))% · "
        }
        // Daily loss limit proximity.
        if Self.dailyLoss < Self.maxDailyLoss * 0.8 {
            s -= 1.0
            why += "Near daily limit · "
        }
        // High correlation concentration → reduce directional conviction.
        if Self.correlationClusterSize > 3 {
            s *= 0.5
            why += "Corr cluster (\(Self.correlationClusterSize)) · "
        }

        // Volatility-adjusted: if ATR is extreme, be cautious.
        let atrPercent = ind.atr14 / (md.currentPrice > 0 ? md.currentPrice : 1) * 100
        if atrPercent > 2.0 {
            s *= 0.7
            why += "High ATR \(String(format: "%.1f", atrPercent))%"
        }

        if why.isEmpty { why = "Risk OK" }
        let conf = 0.6 - min(Self.portfolioDrawdown, 0.4)
        return vote(name, weight, s, conf, why)
    }
}

// MARK: - Whale & Smart-Money Agent
/// Detects unusually large activity patterns from candle footprints:
/// large range + volume bars, absorption signatures, and potential stop-hunt wicks.
struct WhaleSmartMoneyAgent: SignalAgent {
    let name = "Whale"
    let role = "Smart Money / Absorption / Stop Hunts"
    let weight = 1.0
    var isActive = true

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        guard md.candles.count > 10 else {
            return vote(name, weight, 0, 0.3, "insufficient data")
        }

        let n = md.candles.count
        let recent = Array(md.candles[max(0, n - 20)...])
        let avgVolume = recent.map { $0.volume }.filter { $0 > 0 }.reduce(0, +) / max(1, Double(recent.count))
        let avgRange = recent.map { $0.range }.reduce(0, +) / Double(recent.count)

        guard avgVolume > 0, avgRange > 0 else {
            return vote(name, weight, 0, 0.3, "no volume data")
        }

        // Analyze the last 3 candles for whale signatures.
        var s = 0.0
        var whyParts: [String] = []

        for i in max(0, n - 3)..<n {
            let c = md.candles[i]
            let volRatio = avgVolume > 0 ? c.volume / avgVolume : 0
            let rangeRatio = avgRange > 0 ? c.range / avgRange : 0

            // Signature 1: Large volume + small range = absorption (whale absorbing orders)
            if volRatio > 2.0 && rangeRatio < 0.8 {
                let absorptionDir = c.isBullish ? 1.0 : -1.0
                s += absorptionDir * 0.8
                whyParts.append("Absorption \(c.isBullish ? "bid" : "ask")")
            }

            // Signature 2: Stop hunt wick (long wick, close back toward open)
            let bodyRatio = c.range > 0 ? c.body / c.range : 0
            if bodyRatio < 0.3 && volRatio > 1.5 {
                let upperWick = c.high - max(c.open, c.close)
                let lowerWick = min(c.open, c.close) - c.low
                if lowerWick > upperWick * 2 {
                    s += 0.7  // long lower wick = bullish rejection
                    whyParts.append("Lower wick rejection")
                } else if upperWick > lowerWick * 2 {
                    s -= 0.7  // long upper wick = bearish rejection
                    whyParts.append("Upper wick rejection")
                }
            }

            // Signature 3: Volume climax (3x avg volume) with strong close = institutional direction
            if volRatio > 3.0 && rangeRatio > 1.5 {
                s += c.isBullish ? 1.0 : -1.0
                whyParts.append("Climax \(c.isBullish ? "up" : "down")")
            }
        }

        let conf = min(0.5 + Double(whyParts.count) * 0.1, 0.85)
        let why = whyParts.isEmpty ? "No whale activity" : whyParts.joined(separator: " · ")
        return vote(name, weight, s, conf, why)
    }
}

// MARK: - Macro & Correlation Agent
/// Analyzes cross-asset correlations and macro regime for context.
/// Uses price action of correlated assets (when available) to confirm or warn.
struct MacroCorrelationAgent: SignalAgent {
    let name = "Macro"
    let role = "Cross-Asset / Regime Context"
    let weight = 0.75
    var isActive = true

    // Cached correlation data (updated by external feed).
    static var correlations: [String: Double] = [:]  // symbol → correlation coefficient
    static var regimeBias: Direction = .neutral
    static var regimeConfidence: Double = 0.5

    func analyze(_ md: MarketData, _ ind: TechnicalIndicators) -> AgentVote {
        var s = 0.0
        var why = ""

        // Apply stored regime bias (set externally by macro analysis tools).
        switch Self.regimeBias {
        case .strongBullish: s += 1.0; why = "Macro: strong risk-on"
        case .bullish: s += 0.5; why = "Macro: risk-on"
        case .bearish: s -= 0.5; why = "Macro: risk-off"
        case .strongBearish: s -= 1.0; why = "Macro: strong risk-off"
        case .neutral: why = "Macro: neutral"
        }

        // Check correlations for this specific symbol.
        if let corr = Self.correlations[md.symbol] {
            if abs(corr) > 0.7 {
                why += " · High correlation (\(String(format: "%.2f", corr)))"
            }
        }

        // Adapt to asset class.
        switch md.assetClass {
        case .synthetic:
            // Synthetics are less macro-sensitive.
            s *= 0.5
        case .forex:
            // Forex is very macro-sensitive.
            s *= 1.2
        case .crypto:
            // Crypto is risk-asset sensitive.
            s *= 1.1
        case .commodity:
            s *= 0.9
        case .index:
            s *= 1.0
        }

        return vote(name, weight, s, Self.regimeConfidence, why)
    }

    /// Update macro regime from external analysis (called by tools/bots).
    static func setRegime(bias: Direction, confidence: Double) {
        regimeBias = bias
        regimeConfidence = confidence
    }

    /// Update correlation for a symbol.
    static func setCorrelation(symbol: String, coefficient: Double) {
        correlations[symbol] = coefficient
    }
}

// MARK: - Meta Orchestrator Agent
/// NOT a normal agent — this aggregates votes from ALL agents using weighted
/// performance tracking. It dynamically adjusts agent weights based on their
/// historical accuracy per symbol/timeframe. Prevents conflicting signals from
/// producing noise.
struct MetaOrchestrator {
    struct AgentPerformance {
        var correct: Int = 0
        var total: Int = 0
        var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0.5 }
    }

    // agent name → performance history
    static var performanceDB: [String: AgentPerformance] = [:]

    /// Compute dynamic weights for agents based on their track record.
    /// Agents with > 60% accuracy get a 1.2x boost; < 40% get 0.8x penalty.
    static func dynamicWeights(for agents: [SignalAgent]) -> [String: Double] {
        var weights: [String: Double] = [:]
        for agent in agents {
            let perf = performanceDB[agent.name] ?? AgentPerformance()
            let multiplier: Double
            switch perf.accuracy {
            case let a where a > 0.6: multiplier = 1.2
            case let a where a < 0.4: multiplier = 0.8
            default: multiplier = 1.0
            }
            weights[agent.name] = agent.weight * multiplier
        }
        return weights
    }

    /// Blend votes using dynamic weights. Returns a net score -1...1 and confidence.
    static func blend(votes: [AgentVote], symbol: String, timeframe: Timeframe) -> (score: Double, confidence: Double, breakdown: String) {
        // Compute dynamic weights directly from the votes' track records.
        var dynamic: [String: Double] = [:]
        for v in votes {
            let perf = performanceDB[v.agentName] ?? AgentPerformance()
            let multiplier: Double
            switch perf.accuracy {
            case let a where a > 0.6: multiplier = 1.2
            case let a where a < 0.4: multiplier = 0.8
            default: multiplier = 1.0
            }
            dynamic[v.agentName] = v.weight * multiplier
        }

        var bullishScore = 0.0, bearishScore = 0.0, totalWeight = 0.0
        var parts: [String] = []

        for v in votes {
            let w = (dynamic[v.agentName] ?? v.weight) * v.confidence
            totalWeight += v.weight
            switch v.direction {
            case .bullish, .strongBullish:
                bullishScore += w
                parts.append("\(v.agentName):+\(String(format: "%.2f", w))")
            case .bearish, .strongBearish:
                bearishScore += w
                parts.append("\(v.agentName):-\(String(format: "%.2f", w))")
            case .neutral:
                parts.append("\(v.agentName):0")
            }
        }

        let netScore = totalWeight > 0 ? (bullishScore - bearishScore) / totalWeight : 0
        let totalSignal = bullishScore + bearishScore
        let confidence = totalWeight > 0 ? totalSignal / totalWeight : 0

        return (netScore, min(confidence, 0.95), parts.joined(separator: " · "))
    }

    /// Record whether an agent's vote was correct (called after signal resolves).
    static func recordOutcome(agentName: String, wasCorrect: Bool) {
        var perf = performanceDB[agentName] ?? AgentPerformance()
        perf.total += 1
        if wasCorrect { perf.correct += 1 }
        performanceDB[agentName] = perf
    }

    /// Get a human-readable leaderboard of agent accuracy.
    static func leaderboard() -> [(name: String, accuracy: Double, total: Int)] {
        performanceDB.map { (name: $0.key, accuracy: $0.value.accuracy, total: $0.value.total) }
            .sorted { $0.accuracy > $1.accuracy }
    }
}

// MARK: - Extended Agent Factory

enum ExtendedAgentFactory {
    /// The full council: original 12 agents + 6 new specialist agents.
    static func fullCouncil() -> [SignalAgent] {
        AgentFactory.standardCouncil() + [
            OrderFlowAgent(),
            VolatilityRegimeAgent(),
            NewsReactiveAgent(),
            RiskGuardianAgent(),
            WhaleSmartMoneyAgent(),
            MacroCorrelationAgent()
        ]
    }

    /// Agents specifically tuned for synthetic indices (volatility, jump, boom/crash).
    static func syntheticCouncil() -> [SignalAgent] {
        var agents = fullCouncil()
        // Disable macro for synthetics (they don't correlate with DXY etc).
        for i in agents.indices {
            if agents[i].name == "Macro" {
                agents[i].isActive = false
            }
        }
        return agents
    }
}
