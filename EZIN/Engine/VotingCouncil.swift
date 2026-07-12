import Foundation

/// Democratic weighted-voting council — faithful port of council/voting_system.VotingCouncil.
struct VotingCouncil {
    var minConsensus: Double = 0.6
    var minVotesRequired: Int = 4
    var strongSignalThreshold: Double = 0.75

    func deliberate(symbol: String, timeframe: Timeframe, votes: [AgentVote]) -> CouncilDecision? {
        guard votes.count >= minVotesRequired else { return nil }

        var bullish = 0.0, bearish = 0.0, neutral = 0.0, totalWeight = 0.0
        for v in votes {
            let w = v.weight * v.confidence
            totalWeight += v.weight
            switch v.direction {
            case .bullish, .strongBullish:
                bullish += w
                if v.direction == .strongBullish { bullish += w * 0.3 }
            case .bearish, .strongBearish:
                bearish += w
                if v.direction == .strongBearish { bearish += w * 0.3 }
            case .neutral:
                neutral += w
            }
        }
        if totalWeight > 0 { bullish /= totalWeight; bearish /= totalWeight; neutral /= totalWeight }

        let scores: [Direction: Double] = [.bullish: bullish, .bearish: bearish, .neutral: neutral]
        guard let winning = scores.max(by: { $0.value < $1.value }) else { return nil }
        let winDir = winning.key, winScore = winning.value

        var consensus = 0.0
        if winDir != .neutral {
            let opposition = winDir == .bullish ? bearish : bullish
            consensus = (winScore + opposition) > 0 ? winScore / (winScore + opposition) : 0
        }
        guard winDir != .neutral, consensus >= minConsensus else { return nil }

        let strength: SignalStrength
        switch consensus {
        case let c where c >= 0.9: strength = .extreme
        case let c where c >= strongSignalThreshold: strength = .veryStrong
        case let c where c >= 0.68: strength = .strong
        case let c where c >= 0.62: strength = .moderate
        default: strength = .weak
        }

        let dir: Direction = winDir == .bullish
            ? (consensus >= strongSignalThreshold ? .strongBullish : .bullish)
            : (consensus >= strongSignalThreshold ? .strongBearish : .bearish)

        return CouncilDecision(symbol: symbol, timeframe: timeframe, direction: dir,
                               confidence: winScore, consensusRatio: consensus,
                               votes: votes, strength: strength)
    }
}
