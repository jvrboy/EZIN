import XCTest
@testable import EZIN

// MARK: - SignalEngine Tests

final class SignalEngineTests: XCTestCase {
    var engine: SignalEngine!

    override func setUp() {
        super.setUp()
        engine = SignalEngine()
    }

    func testGenerateReturnsNilForInsufficientData() {
        let md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: [])
        let signal = engine.generate(for: md)
        XCTAssertNil(signal)
    }

    func testGenerateReturnsNilForFlatMarket() {
        // Create flat candles (no trend)
        let candles = (0..<30).map { i in
            Candle(timestamp: Date().addingTimeInterval(-Double(30 - i) * 300),
                   open: 100.0, high: 100.5, low: 99.5, close: 100.0, volume: 100)
        }
        var md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: candles)
        md.currentPrice = 100.0
        let signal = engine.generate(for: md)
        // Flat market should not produce a signal
        XCTAssertNil(signal)
    }

    func testGenerateProducesBullishSignalForUptrend() {
        // Create uptrend candles
        var candles: [Candle] = []
        var price = 100.0
        for i in 0..<50 {
            price += Double.random(in: 0.1...0.5)
            let o = price - Double.random(in: 0...0.3)
            let c = price
            let h = max(o, c) + Double.random(in: 0...0.2)
            let l = min(o, c) - Double.random(in: 0...0.2)
            candles.append(Candle(timestamp: Date().addingTimeInterval(-Double(50 - i) * 300),
                                  open: o, high: h, low: l, close: c, volume: Double.random(in: 50...200)))
        }
        var md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: candles)
        md.currentPrice = price
        let signal = engine.generate(for: md)
        XCTAssertNotNil(signal)
        XCTAssertTrue(signal?.isBuy == true, "Expected bullish signal in uptrend")
        XCTAssertGreaterThan(signal?.confidence ?? 0, 0)
    }

    func testSignalHasValidStopLossAndTakeProfit() {
        var candles: [Candle] = []
        var price = 100.0
        for i in 0..<50 {
            price += 0.3
            candles.append(Candle(timestamp: Date().addingTimeInterval(-Double(50 - i) * 300),
                                  open: price - 0.2, high: price + 0.3, low: price - 0.4,
                                  close: price, volume: 100))
        }
        var md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: candles)
        md.currentPrice = price
        guard let signal = engine.generate(for: md) else {
            XCTFail("Expected signal")
            return
        }
        XCTAssertGreaterThan(signal.entry, 0)
        XCTAssertGreaterThan(signal.stopLoss, 0)
        XCTAssertGreaterThan(signal.takeProfit, 0)
        // For a buy signal, TP should be above entry and SL below
        if signal.isBuy {
            XCTAssertGreaterThan(signal.takeProfit, signal.entry)
            XCTAssertLessThan(signal.stopLoss, signal.entry)
        }
        XCTAssertGreaterThan(signal.riskReward, 0)
    }

    func testMinConfidenceThreshold() {
        engine.minConfidence = 0.95 // Very high threshold
        var candles: [Candle] = []
        var price = 100.0
        for i in 0..<50 {
            price += 0.1
            candles.append(Candle(timestamp: Date().addingTimeInterval(-Double(50 - i) * 300),
                                  open: price - 0.2, high: price + 0.3, low: price - 0.4,
                                  close: price, volume: 100))
        }
        var md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: candles)
        md.currentPrice = price
        let signal = engine.generate(for: md)
        // With very high threshold, should be nil
        XCTAssertNil(signal)
    }
}

// MARK: - VotingCouncil Tests

final class VotingCouncilTests: XCTestCase {
    var council: VotingCouncil!

    override func setUp() {
        super.setUp()
        council = VotingCouncil()
    }

    func testDeliberateReturnsNilForEmptyVotes() {
        let result = council.deliberate(symbol: "R_100", timeframe: .m5, votes: [])
        XCTAssertNil(result)
    }

    func testDeliberateRequiresMinimumVotes() {
        council.minVotesRequired = 5
        let votes = [
            AgentVote(agentName: "Trend", direction: .bullish, confidence: 0.8, weight: 1.0, rationale: "Up"),
            AgentVote(agentName: "Momentum", direction: .bullish, confidence: 0.7, weight: 1.0, rationale: "Up")
        ]
        let result = council.deliberate(symbol: "R_100", timeframe: .m5, votes: votes)
        XCTAssertNil(result)
    }

    func testStrongBullishConsensus() {
        let votes = [
            AgentVote(agentName: "Trend", direction: .strongBullish, confidence: 0.9, weight: 1.2, rationale: "Strong up"),
            AgentVote(agentName: "Momentum", direction: .strongBullish, confidence: 0.85, weight: 1.0, rationale: "Strong up"),
            AgentVote(agentName: "Volume", direction: .bullish, confidence: 0.7, weight: 0.7, rationale: "Up"),
            AgentVote(agentName: "Structure", direction: .bullish, confidence: 0.75, weight: 0.9, rationale: "Up"),
            AgentVote(agentName: "Ichimoku", direction: .bullish, confidence: 0.8, weight: 1.1, rationale: "Up")
        ]
        guard let result = council.deliberate(symbol: "R_100", timeframe: .m5, votes: votes) else {
            XCTFail("Expected decision")
            return
        }
        XCTAssertTrue(result.direction.isBullish)
        XCTAssertGreaterThanOrEqual(result.consensusRatio, 0.6)
        XCTAssertGreaterThan(result.confidence, 0)
    }

    func testNeutralVotesReduceConsensus() {
        let votes = [
            AgentVote(agentName: "Trend", direction: .bullish, confidence: 0.6, weight: 1.0, rationale: "Weak up"),
            AgentVote(agentName: "Momentum", direction: .neutral, confidence: 0.5, weight: 1.0, rationale: "Flat"),
            AgentVote(agentName: "Volume", direction: .neutral, confidence: 0.5, weight: 0.7, rationale: "Flat"),
            AgentVote(agentName: "Structure", direction: .bullish, confidence: 0.6, weight: 0.9, rationale: "Weak up")
        ]
        let result = council.deliberate(symbol: "R_100", timeframe: .m5, votes: votes)
        // With many neutral votes, consensus might not reach threshold
        if let r = result {
            XCTAssertTrue(r.direction.isBullish || r.direction == .neutral)
        }
    }

    func testConflictingVotes() {
        let votes = [
            AgentVote(agentName: "Trend", direction: .bullish, confidence: 0.9, weight: 1.2, rationale: "Up"),
            AgentVote(agentName: "Momentum", direction: .bearish, confidence: 0.9, weight: 1.0, rationale: "Down"),
            AgentVote(agentName: "Volume", direction: .bullish, confidence: 0.7, weight: 0.7, rationale: "Up"),
            AgentVote(agentName: "Structure", direction: .bearish, confidence: 0.8, weight: 0.9, rationale: "Down")
        ]
        let result = council.deliberate(symbol: "R_100", timeframe: .m5, votes: votes)
        // Conflicting votes may not reach consensus
        if let r = result {
            XCTAssertLessThan(r.consensusRatio, 0.9)
        }
    }
}

// MARK: - SignalTracker Tests

final class SignalTrackerTests: XCTestCase {
    var tracker: SignalTracker!

    override func setUp() {
        super.setUp()
        tracker = SignalTracker()
    }

    func testTrackSignal() {
        let signal = createTestSignal(type: .buy, entry: 100.0, stopLoss: 98.0, takeProfit: 104.0)
        tracker.trackSignal(signal, currentPrice: 100.0)

        XCTAssertEqual(tracker.activeSignals.count, 1)
        XCTAssertEqual(tracker.activeSignals.first?.entryPrice, 100.0)
        XCTAssertEqual(tracker.metrics.totalSignals, 1)
    }

    func testSignalHitTakeProfit() {
        let signal = createTestSignal(type: .buy, entry: 100.0, stopLoss: 98.0, takeProfit: 104.0)
        tracker.trackSignal(signal, currentPrice: 100.0)

        // Price rises to TP
        tracker.updateSignalPrice(tracker.activeSignals.first!.id, currentPrice: 104.5)

        XCTAssertEqual(tracker.activeSignals.count, 0)
        XCTAssertEqual(tracker.closedSignals.count, 1)
        XCTAssertTrue(tracker.closedSignals.first?.isWinning == true)
        XCTAssertEqual(tracker.metrics.winningSignals, 1)
    }

    func testSignalHitStopLoss() {
        let signal = createTestSignal(type: .buy, entry: 100.0, stopLoss: 98.0, takeProfit: 104.0)
        tracker.trackSignal(signal, currentPrice: 100.0)

        // Price drops to SL
        tracker.updateSignalPrice(tracker.activeSignals.first!.id, currentPrice: 97.5)

        XCTAssertEqual(tracker.activeSignals.count, 0)
        XCTAssertEqual(tracker.closedSignals.count, 1)
        XCTAssertTrue(tracker.closedSignals.first?.isWinning == false)
        XCTAssertEqual(tracker.metrics.losingSignals, 1)
    }

    func testSellSignalHitTakeProfit() {
        let signal = createTestSignal(type: .sell, entry: 100.0, stopLoss: 102.0, takeProfit: 96.0)
        tracker.trackSignal(signal, currentPrice: 100.0)

        // Price drops to TP (for sell, TP is below entry)
        tracker.updateSignalPrice(tracker.activeSignals.first!.id, currentPrice: 95.5)

        XCTAssertTrue(tracker.closedSignals.first?.isWinning == true)
    }

    func testRecommendationsNeedMinimumSignals() {
        let recs = tracker.getImprovementRecommendations()
        XCTAssertTrue(recs.first?.contains("at least 10") == true)
    }

    // MARK: Helpers

    private func createTestSignal(type: SignalType, entry: Double, stopLoss: Double, takeProfit: Double) -> TradingSignal {
        TradingSignal(
            symbol: "R_100",
            displayPair: "Volatility 100",
            type: type,
            entry: entry,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            confidence: 75,
            strategy: "Test",
            timeframe: .m5,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}

// MARK: - DerivError Tests

final class DerivErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertEqual(DerivError.timeout.localizedDescription, "Request timed out")
        XCTAssertEqual(DerivError.notConnected.localizedDescription, "Not connected to Deriv")
        XCTAssertEqual(DerivError.connectionDropped.localizedDescription, "Connection dropped before a response arrived")
        XCTAssertEqual(DerivError.api("test error").localizedDescription, "test error")
    }
}

// MARK: - Candle Tests

final class CandleTests: XCTestCase {
    func testCandleProperties() {
        let bullish = Candle(timestamp: Date(), open: 100, high: 105, low: 99, close: 104, volume: 1000)
        XCTAssertTrue(bullish.isBullish)
        XCTAssertFalse(bullish.isBearish)
        XCTAssertEqual(bullish.body, 4)
        XCTAssertEqual(bullish.range, 6)

        let bearish = Candle(timestamp: Date(), open: 104, high: 105, low: 99, close: 100, volume: 1000)
        XCTAssertTrue(bearish.isBearish)
        XCTAssertFalse(bearish.isBullish)
        XCTAssertEqual(bearish.body, 4)
    }
}

// MARK: - Direction Tests

final class DirectionTests: XCTestCase {
    func testDirectionProperties() {
        XCTAssertTrue(Direction.strongBullish.isBullish)
        XCTAssertTrue(Direction.bullish.isBullish)
        XCTAssertFalse(Direction.neutral.isBullish)
        XCTAssertTrue(Direction.strongBearish.isBearish)
        XCTAssertTrue(Direction.bearish.isBearish)
        XCTAssertFalse(Direction.neutral.isBearish)
    }
}

// MARK: - APITokenTracker Tests

final class APITokenTrackerTests: XCTestCase {
    var tracker: APITokenTracker!

    override func setUp() {
        super.setUp()
        tracker = APITokenTracker.shared
        tracker.resetAll()
    }

    func testRecordUsage() {
        tracker.recordUsage(provider: .openAI, keyId: "test_key_1", tokensUsed: 150)

        let stats = tracker.aggregate(for: .openAI)
        XCTAssertEqual(stats.totalRequests, 1)
        XCTAssertEqual(stats.totalTokensUsed, 150)
    }

    func testMarkRateLimited() {
        tracker.markRateLimited(provider: .groq, keyId: "test_key", retryAfter: 120)

        XCTAssertFalse(tracker.isKeyUsable(provider: .groq, keyId: "test_key"))
    }

    func testMarkHealthy() {
        tracker.markRateLimited(provider: .groq, keyId: "test_key", retryAfter: 120)
        tracker.markHealthy(provider: .groq, keyId: "test_key")

        XCTAssertTrue(tracker.isKeyUsable(provider: .groq, keyId: "test_key"))
    }

    func testConsecutiveErrorsMakeUnhealthy() {
        for _ in 0..<5 {
            tracker.recordError(provider: .openAI, keyId: "fragile_key")
        }

        XCTAssertFalse(tracker.isKeyUsable(provider: .openAI, keyId: "fragile_key"))
    }

    func testAggregateAcrossMultipleKeys() {
        tracker.recordUsage(provider: .openAI, keyId: "key_1", tokensUsed: 100)
        tracker.recordUsage(provider: .openAI, keyId: "key_2", tokensUsed: 200)
        tracker.recordUsage(provider: .groq, keyId: "key_1", tokensUsed: 50)

        let openAIStats = tracker.aggregate(for: .openAI)
        XCTAssertEqual(openAIStats.totalKeys, 2)
        XCTAssertEqual(openAIStats.totalRequests, 2)
        XCTAssertEqual(openAIStats.totalTokensUsed, 300)

        let groqStats = tracker.aggregate(for: .groq)
        XCTAssertEqual(groqStats.totalKeys, 1)
        XCTAssertEqual(groqStats.totalRequests, 1)
    }
}
