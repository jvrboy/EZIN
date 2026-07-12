import Foundation

/// Main signal generation engine — port of signals/signal_engine.SignalEngine.
/// Pipeline: indicators -> agents -> council -> signal.
final class SignalEngine {
    var agents: [SignalAgent] = AgentFactory.standardCouncil()
    var council = VotingCouncil()
    let analyzer = TechnicalAnalyzer()
    var minConfidence: Double = 0.65
    var stopLossATR: Double = 2.0
    var takeProfitATR: Double = 3.0
    var expiryMinutes: Int = 30

    func generate(for md: MarketData, strategyName: String = "Council Consensus") -> TradingSignal? {
        let ind = analyzer.analyze(md)

        // Collect votes from active agents.
        let votes = agents.filter { $0.isActive }.map { $0.analyze(md, ind) }
        guard votes.count >= 4 else { return nil }

        guard let decision = council.deliberate(symbol: md.symbol, timeframe: md.timeframe, votes: votes),
              decision.confidence >= minConfidence else { return nil }

        let price = md.currentPrice > 0 ? md.currentPrice : (md.latest?.close ?? 0)
        guard price > 0 else { return nil }
        let atr = ind.atr14 > 0 ? ind.atr14 : price * 0.001
        let isBuy = decision.direction.isBullish

        let sl = isBuy ? price - atr * stopLossATR : price + atr * stopLossATR
        let tp = isBuy ? price + atr * takeProfitATR : price - atr * takeProfitATR

        let type: SignalType
        switch decision.direction {
        case .strongBullish: type = .strongBuy
        case .bullish: type = .buy
        case .strongBearish: type = .strongSell
        case .bearish: type = .sell
        case .neutral: return nil
        }

        return TradingSignal(
            symbol: md.symbol,
            displayPair: DerivSymbols.display(md.symbol),
            type: type,
            entry: price,
            stopLoss: sl,
            takeProfit: tp,
            confidence: (decision.consensusRatio * 100).rounded(),
            strategy: strategyName,
            timeframe: md.timeframe,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(expiryMinutes * 60))
        )
    }

    /// Snapshot of agent states for the (hidden) Bot dashboard.
    func botDescriptors(lastVotes: [AgentVote]) -> [BotDescriptor] {
        agents.map { a in
            let v = lastVotes.first { $0.agentName == a.name }
            let label: String
            switch v?.direction {
            case .strongBullish, .bullish: label = "BULL"
            case .strongBearish, .bearish: label = "BEAR"
            default: label = "FLAT"
            }
            return BotDescriptor(name: a.name, role: a.role, active: a.isActive, lastVote: label)
        }
    }
}
