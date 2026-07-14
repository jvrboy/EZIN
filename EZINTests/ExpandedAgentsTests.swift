import XCTest
@testable import EZIN

final class ExpandedAgentsTests: XCTestCase {
    private func marketData() -> MarketData {
        let candles = (0..<80).map { index in
            let close = 100 + Double(index) * 0.2
            return Candle(
                timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 60)),
                open: close - 0.1,
                high: close + 0.3,
                low: close - 0.3,
                close: close,
                volume: 1_000 + Double(index) * 10
            )
        }
        return MarketData(
            symbol: "R_100",
            assetClass: .synthetic,
            timeframe: .m1,
            candles: candles,
            currentPrice: candles.last?.close ?? 0
        )
    }

    func testRegimeAgentConfirmsEfficientUptrend() {
        var indicators = TechnicalIndicators.empty
        indicators.ema12 = 110
        indicators.ema26 = 105
        indicators.choppinessIndex = 35
        indicators.efficiencyRatio = 0.7

        let result = RegimeAgent().analyze(marketData(), indicators)
        XCTAssertTrue(result.direction.isBullish)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testRegimeAgentStaysNeutralInChop() {
        var indicators = TechnicalIndicators.empty
        indicators.ema12 = 110
        indicators.ema26 = 105
        indicators.choppinessIndex = 65
        indicators.efficiencyRatio = 0.15

        let result = RegimeAgent().analyze(marketData(), indicators)
        XCTAssertEqual(result.direction, .neutral)
    }

    func testDirectionalAgentRequiresAroonAndVortexAgreement() {
        var indicators = TechnicalIndicators.empty
        indicators.aroonOscillator = -70
        indicators.vortexPlus = 0.75
        indicators.vortexMinus = 1.25

        let result = DirectionalAgent().analyze(marketData(), indicators)
        XCTAssertTrue(result.direction.isBearish)
    }

    func testParticipationAgentGatesLowRelativeVolume() {
        var indicators = TechnicalIndicators.empty
        indicators.relativeVolume = 0.9
        indicators.forceIndex = 100
        indicators.cmf = 0.2

        let result = ParticipationAgent().analyze(marketData(), indicators)
        XCTAssertEqual(result.direction, .neutral)
        XCTAssertLessThan(result.confidence, 0.5)
    }

    func testNormalizedMomentumAgentPenalizesExtremeExtension() {
        var moderate = TechnicalIndicators.empty
        moderate.ppoHistogram = 1.2
        moderate.fisherTransform = 1
        moderate.priceZScore = 1

        var extended = moderate
        extended.priceZScore = 5

        let agent = NormalizedMomentumAgent()
        let moderateVote = agent.analyze(marketData(), moderate)
        let extendedVote = agent.analyze(marketData(), extended)
        XCTAssertTrue(moderateVote.direction.isBullish)
        XCTAssertLessThan(extendedVote.confidence, moderateVote.confidence)
    }
}
