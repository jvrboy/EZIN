import XCTest
@testable import EZIN

/// Deterministic tests for the weighted-voting council — the component that ultimately
/// decides BUY vs SELL for real-money signals. No network, no randomness.
final class VotingCouncilTests: XCTestCase {

    private func vote(_ dir: Direction, confidence: Double = 1.0, weight: Double = 1.0) -> AgentVote {
        AgentVote(agentName: "test", direction: dir, confidence: confidence, weight: weight, rationale: "")
    }

    private let council = VotingCouncil()

    func testUnanimousBullishProducesStrongBuy() {
        let votes = Array(repeating: vote(.bullish), count: 5)
        let decision = council.deliberate(symbol: "R_75", timeframe: .m5, votes: votes)
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision!.direction.isBullish)
        XCTAssertEqual(decision!.direction, .strongBullish)
        XCTAssertEqual(decision!.consensusRatio, 1.0, accuracy: 1e-9)
        XCTAssertEqual(decision!.strength, .extreme)
    }

    func testUnanimousBearishProducesStrongSell() {
        let votes = Array(repeating: vote(.bearish), count: 5)
        let decision = council.deliberate(symbol: "R_75", timeframe: .m5, votes: votes)
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision!.direction.isBearish)
        XCTAssertEqual(decision!.direction, .strongBearish)
    }

    func testTooFewVotesReturnsNil() {
        let votes = Array(repeating: vote(.bullish), count: 3) // below minVotesRequired (4)
        XCTAssertNil(council.deliberate(symbol: "R_75", timeframe: .m5, votes: votes))
    }

    func testBalancedVotesReturnNilBecauseConsensusTooLow() {
        // 2 bull vs 2 bear => consensus 0.5, below minConsensus (0.6).
        let votes = [vote(.bullish), vote(.bullish), vote(.bearish), vote(.bearish)]
        XCTAssertNil(council.deliberate(symbol: "R_75", timeframe: .m5, votes: votes))
    }

    func testMajorityBullishCrossesConsensusThreshold() {
        // 3 bull vs 1 bear => consensus 0.75.
        let votes = [vote(.bullish), vote(.bullish), vote(.bullish), vote(.bearish)]
        let decision = council.deliberate(symbol: "R_75", timeframe: .m5, votes: votes)
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision!.direction.isBullish)
        XCTAssertEqual(decision!.consensusRatio, 0.75, accuracy: 1e-9)
        XCTAssertEqual(decision!.strength, .veryStrong)
    }

    func testConfidenceWeightsTiltTheOutcome() {
        // Low-confidence bears cannot outweigh high-confidence bulls.
        let votes = [
            vote(.bullish, confidence: 1.0, weight: 1.0),
            vote(.bullish, confidence: 1.0, weight: 1.0),
            vote(.bearish, confidence: 0.1, weight: 1.0),
            vote(.bearish, confidence: 0.1, weight: 1.0)
        ]
        let decision = council.deliberate(symbol: "R_75", timeframe: .m5, votes: votes)
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision!.direction.isBullish)
    }
}
