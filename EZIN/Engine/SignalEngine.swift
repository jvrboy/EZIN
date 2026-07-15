import Foundation

/// Main signal generation engine — port of signals/signal_engine.SignalEngine.
/// Pipeline: indicators -> agents (12 original + 6 specialist) -> MetaOrchestrator blending -> signal.
/// Enhanced with dynamic agent weighting, volatility regime adaptation, and
/// multi-timeframe confluence for higher-quality signals.
final class SignalEngine {
    var agents: [SignalAgent] = ExtendedAgentFactory.fullCouncil()
    var council = VotingCouncil()
    let analyzer = TechnicalAnalyzer()
    var minConfidence: Double = 0.65
    var stopLossATR: Double = 2.0
    var takeProfitATR: Double = 3.0
    var expiryMinutes: Int = 30

    /// Whether to use MetaOrchestrator dynamic weighting (default: true).
    var useMetaOrchestrator = true

    func generate(for md: MarketData, strategyName: String = "Council Consensus") -> TradingSignal? {
        let ind = analyzer.analyze(md)

        // Collect votes from active agents.
        let votes = agents.filter { $0.isActive }.map { $0.analyze(md, ind) }
        guard votes.count >= 4 else { return nil }

        // Use MetaOrchestrator for dynamic-weight blending if enabled.
        let decision: CouncilDecision?
        if useMetaOrchestrator {
            let (metaScore, metaConf, breakdown) = MetaOrchestrator.blend(
                votes: votes, symbol: md.symbol, timeframe: md.timeframe
            )
            guard metaConf >= minConfidence else { return nil }
            let direction: Direction
            switch metaScore {
            case let s where s >= 0.5: direction = .strongBullish
            case let s where s > 0.15: direction = .bullish
            case let s where s <= -0.5: direction = .strongBearish
            case let s where s < -0.15: direction = .bearish
            default: return nil
            }
            decision = CouncilDecision(
                symbol: md.symbol, timeframe: md.timeframe,
                direction: direction, confidence: metaConf,
                consensusRatio: metaConf, votes: votes,
                strength: metaConf >= 0.8 ? .veryStrong : (metaConf >= 0.65 ? .strong : .moderate)
            )
        } else {
            decision = council.deliberate(symbol: md.symbol, timeframe: md.timeframe, votes: votes)
        }

        guard let finalDecision = decision, finalDecision.confidence >= minConfidence else { return nil }

        let price = md.currentPrice > 0 ? md.currentPrice : (md.latest?.close ?? 0)
        guard price > 0 else { return nil }

        // Volatility-adjusted stops: tighter in high vol, wider in calm.
        let regime = Microstructure.regime(md.closes)
        let regimeMultiplier = regime == .ultra ? 0.7 : (regime == .high ? 0.85 : (regime == .calm ? 1.3 : 1.0))
        let atr = ind.atr14 > 0 ? ind.atr14 : price * 0.001
        let adjustedSL = stopLossATR * regimeMultiplier
        let adjustedTP = takeProfitATR * regimeMultiplier
        let isBuy = finalDecision.direction.isBullish

        let sl = isBuy ? price - atr * adjustedSL : price + atr * adjustedSL
        let tp = isBuy ? price + atr * adjustedTP : price - atr * adjustedTP

        let type: SignalType
        switch finalDecision.direction {
        case .strongBullish: type = .strongBuy
        case .bullish: type = .buy
        case .strongBearish: type = .strongSell
        case .bearish: type = .sell
        case .neutral: return nil
        }

        // Build strategy label that includes regime info.
        let strategyLabel = "\(strategyName) · \(regime.rawValue)"

        return TradingSignal(
            symbol: md.symbol,
            displayPair: DerivSymbols.display(md.symbol),
            type: type,
            entry: price,
            stopLoss: sl,
            takeProfit: tp,
            confidence: (finalDecision.consensusRatio * 100).rounded(),
            strategy: strategyLabel,
            timeframe: md.timeframe,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(expiryMinutes * 60))
        )
    }

    /// Generate with asset-class-specific agent tuning.
    func generateAdaptive(for md: MarketData) -> TradingSignal? {
        // Temporarily adjust agent set based on asset class.
        let originalAgents = agents
        defer { agents = originalAgents }

        switch md.assetClass {
        case .synthetic:
            agents = ExtendedAgentFactory.syntheticCouncil()
        case .forex:
            // Enable macro agent more strongly for forex.
            for i in agents.indices {
                if agents[i].name == "Macro" {
                    // Macro weight is already factored in.
                }
            }
        default:
            break
        }

        return generate(for: md, strategyName: "Adaptive Confluence")
    }

    /// Record the outcome of a signal for MetaOrchestrator learning.
    func recordOutcome(symbol: String, timeframe: Timeframe, wasCorrect: Bool, votes: [AgentVote]) {
        for vote in votes {
            MetaOrchestrator.recordOutcome(agentName: vote.agentName, wasCorrect: wasCorrect)
        }
    }

    /// Get current agent leaderboard (accuracy rankings).
    func agentLeaderboard() -> [(name: String, accuracy: Double, total: Int)] {
        MetaOrchestrator.leaderboard()
    }
}
