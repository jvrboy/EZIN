import XCTest
@testable import EZIN

final class ExtendedIndicatorsTests: XCTestCase {
    func testPPOIsZeroForConstantSeries() {
        let values = [Double](repeating: 42, count: 80)
        let result = Indicators.ppo(values)
        XCTAssertEqual(result.line.count, values.count)
        XCTAssertEqual(result.signal.count, values.count)
        XCTAssertEqual(result.histogram.count, values.count)
        XCTAssertTrue(result.line.allSatisfy { abs($0) < 1e-9 })
        XCTAssertTrue(result.histogram.allSatisfy { abs($0) < 1e-9 })
    }

    func testZScoreIsFiniteAndAligned() {
        let values = (1...60).map(Double.init)
        let result = Indicators.zScore(values, 20)
        XCTAssertEqual(result.count, values.count)
        XCTAssertTrue(result.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(result.last ?? 0, 0)
    }

    func testEfficiencyRatioIsOneForMonotonicSeries() {
        let values = (0...30).map(Double.init)
        let result = Indicators.efficiencyRatio(values, 10)
        XCTAssertEqual(result.count, values.count)
        XCTAssertEqual(result.last ?? 0, 1, accuracy: 1e-9)
    }

    func testFisherTransformHandlesShortAndFlatSeries() {
        XCTAssertTrue(Indicators.fisherTransform([], []).isEmpty)
        let result = Indicators.fisherTransform([2, 2, 2], [2, 2, 2], 10)
        XCTAssertEqual(result, [0, 0, 0])
    }

    func testAroonDetectsNewestHighAndOldestLow() {
        let high = [1, 2, 3, 4, 5, 6].map(Double.init)
        let low = [0, 1, 2, 3, 4, 5].map(Double.init)
        let result = Indicators.aroon(high, low, 3)
        XCTAssertEqual(result.up.last ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(result.down.last ?? 100, 0, accuracy: 1e-9)
        XCTAssertEqual(result.oscillator.last ?? 0, 100, accuracy: 1e-9)
    }

    func testVortexAndChoppinessRemainAlignedAndFinite() {
        let close = (1...40).map { Double($0) }
        let high = close.map { $0 + 0.5 }
        let low = close.map { $0 - 0.5 }
        let vortex = Indicators.vortex(high, low, close, 14)
        let chop = Indicators.choppinessIndex(high, low, close, 14)

        XCTAssertEqual(vortex.plus.count, close.count)
        XCTAssertEqual(vortex.minus.count, close.count)
        XCTAssertEqual(chop.count, close.count)
        XCTAssertTrue(vortex.plus.allSatisfy(\.isFinite))
        XCTAssertTrue(vortex.minus.allSatisfy(\.isFinite))
        XCTAssertTrue(chop.allSatisfy(\.isFinite))
        XCTAssertLessThan(chop.last ?? 100, 50)
    }
}
