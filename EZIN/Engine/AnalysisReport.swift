import Foundation

// MARK: - Structured multi-timeframe analysis report
//
// Produced by MultiTimeframeEngine. Every requested analysis walks the FULL
// timeframe ladder, deep-dives each timeframe, reads the 1-minute execution
// timing, then merges everything into one final verdict.

/// Deep snapshot for a single timeframe.
struct TimeframeSnapshot {
    let timeframe: Timeframe
    let price: Double

    // Direction & bias
    let direction: Direction
    let biasText: String
    let councilConfidence: Double     // 0…1
    let consensus: Double             // 0…1
    let strength: SignalStrength

    // Momentum / trend / volume dimensions
    let momentumScore: Double         // −1…1
    let momentumLabel: String
    let trendStrength: Double         // ADX-blended 0…100
    let volumeBiasText: String
    let regime: Microstructure.VolatilityRegime
    let realizedVol: Double
    let speed: Double                 // price velocity %
    let accel: Double

    // Key levels
    let support: Double
    let resistance: Double
    let poc: Double
    let valueAreaHigh: Double
    let valueAreaLow: Double

    // Order flow
    let orderFlowBias: Direction
    let netAggressiveVolume: Double
    let tradeDirectionRatio: Double

    // Confluence contribution (signed, weighted by timeframe authority)
    let weightedScore: Double

    // Top agent rationales
    let topVotes: [AgentVote]
}

/// Cross-timeframe confluence result.
struct MTFConfluence {
    let alignmentScore: Double        // −1 (all bearish) … +1 (all bullish)
    let bullishTFs: Int
    let bearishTFs: Int
    let neutralTFs: Int
    let dominantDirection: Direction
    let agreementPct: Int             // % of timeframes agreeing with dominant
    let higherTFBias: Direction       // bias of h1/h4/d1 block
    let notes: [String]
}

/// The one-minute execution timing read.
struct ExecutionRead {
    let direction: Direction
    let momentumLabel: String
    let speed: Double
    let accel: Double
    let immediateLevelAbove: Double
    let immediateLevelBelow: Double
    let jumpRisk: Bool
    let text: String
}

/// The merged final decision.
struct FinalVerdict {
    let action: SignalType            // buy / sell / hold (+strong variants)
    let direction: Direction
    let confidence: Int               // 0…100
    let requestedTimeframe: Timeframe
    let entry: Double
    let stopLoss: Double
    let takeProfit: Double
    let riskReward: Double
    let rationale: [String]           // ordered bullet reasoning
    let warnings: [String]
}

/// The full deep report the engine returns.
struct AnalysisReport {
    let symbol: String
    let displaySymbol: String
    let assetClass: AssetClass
    let requestedTimeframe: Timeframe
    let generatedAt: Date

    let perTimeframe: [TimeframeSnapshot]
    let executionRead: ExecutionRead
    let requestedFocus: TimeframeSnapshot
    let confluence: MTFConfluence
    let verdict: FinalVerdict
}
