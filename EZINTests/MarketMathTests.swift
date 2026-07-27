import XCTest
@testable import EZIN

/// Deterministic tests for MarketMath — the pure math layer behind the chat
/// market tool pack (fib levels, pivots, streaks, risk/reward, Kelly).
final class MarketMathTests: XCTestCase {

    // MARK: - Fibonacci

    func testFibonacciUpLegRetracements() {
        let fib = MarketMath.fibonacci(high: 200, low: 100, isUpLeg: true)
        // 50% retrace of an up-leg from 100→200 sits at 150.
        let half = fib.retracements.first { $0.ratio == 0.5 }!
        XCTAssertEqual(half.price, 150, accuracy: 1e-9)
        // 61.8% retrace = 200 − 61.8 = 138.2
        let golden = fib.retracements.first { $0.ratio == 0.618 }!
        XCTAssertEqual(golden.price, 138.2, accuracy: 1e-9)
        // 161.8% extension = 100 + 161.8 = 261.8
        let ext = fib.extensions.first { $0.ratio == 1.618 }!
        XCTAssertEqual(ext.price, 261.8, accuracy: 1e-9)
    }

    func testFibonacciDownLegMirrors() {
        let fib = MarketMath.fibonacci(high: 200, low: 100, isUpLeg: false)
        let half = fib.retracements.first { $0.ratio == 0.5 }!
        XCTAssertEqual(half.price, 150, accuracy: 1e-9)
        // Down-leg 61.8% retrace bounces UP from the low: 100 + 61.8 = 161.8
        let golden = fib.retracements.first { $0.ratio == 0.618 }!
        XCTAssertEqual(golden.price, 161.8, accuracy: 1e-9)
        // Down-leg extension projects below the high: 200 − 161.8 = 38.2
        let ext = fib.extensions.first { $0.ratio == 1.618 }!
        XCTAssertEqual(ext.price, 38.2, accuracy: 1e-9)
    }

    // MARK: - Pivots

    func testClassicPivots() {
        let p = MarketMath.classicPivots(high: 110, low: 90, close: 100)
        XCTAssertEqual(p.pivot, 100, accuracy: 1e-9)          // (110+90+100)/3
        XCTAssertEqual(p.r1, 110, accuracy: 1e-9)             // 2·100 − 90
        XCTAssertEqual(p.s1, 90, accuracy: 1e-9)              // 2·100 − 110
        XCTAssertEqual(p.r2, 120, accuracy: 1e-9)             // 100 + (110−90)
        XCTAssertEqual(p.s2, 80, accuracy: 1e-9)
        XCTAssertEqual(p.r3, 130, accuracy: 1e-9)             // 110 + 2·(100−90)
        XCTAssertEqual(p.s3, 70, accuracy: 1e-9)              // 90 − 2·(110−100)
    }

    func testWoodiePivotWeightsClose() {
        let p = MarketMath.woodiePivots(high: 110, low: 90, close: 104)
        XCTAssertEqual(p.pivot, (110 + 90 + 2 * 104) / 4, accuracy: 1e-9)
    }

    func testCamarillaBandsAreSymmetric() {
        let p = MarketMath.camarillaPivots(high: 110, low: 90, close: 100)
        XCTAssertEqual(p.r1 - 100, 100 - p.s1, accuracy: 1e-9)
        XCTAssertEqual(p.r3 - 100, 100 - p.s3, accuracy: 1e-9)
        XCTAssertGreaterThan(p.r3, p.r2)
        XCTAssertGreaterThan(p.r2, p.r1)
    }

    // MARK: - Streaks

    func testStreaksBasicPattern() {
        // up, up, down, up  →  dirs [1, 1, -1, 1]
        let s = MarketMath.streaks(closes: [1, 2, 3, 2, 4])
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertEqual(s.maxUpStreak, 2)
        XCTAssertEqual(s.maxDownStreak, 1)
        XCTAssertEqual(s.upBars, 3)
        XCTAssertEqual(s.downBars, 1)
        // After an up bar: transitions at i=1 (up) and i=2 (down) → P(up|up) = 1/2.
        XCTAssertEqual(s.upAfterUp, 0.5, accuracy: 1e-9)
        // After a down bar: one transition (i=3, up) → P(up|down) = 1.
        XCTAssertEqual(s.upAfterDown, 1.0, accuracy: 1e-9)
    }

    func testStreaksAllDown() {
        let s = MarketMath.streaks(closes: [5, 4, 3, 2, 1])
        XCTAssertEqual(s.currentStreak, -4)
        XCTAssertEqual(s.maxDownStreak, 4)
        XCTAssertEqual(s.maxUpStreak, 0)
        XCTAssertEqual(s.upAfterDown, 0, accuracy: 1e-9)
    }

    func testStreaksEmptyAndFlatAreSafe() {
        let empty = MarketMath.streaks(closes: [])
        XCTAssertEqual(empty.currentStreak, 0)
        let flat = MarketMath.streaks(closes: [3, 3, 3])
        XCTAssertEqual(flat.upBars, 0)
        XCTAssertEqual(flat.downBars, 0)
    }

    // MARK: - Risk / reward

    func testRiskRewardLong() {
        let rr = MarketMath.riskReward(entry: 100, stop: 95, target: 115)!
        XCTAssertTrue(rr.isLong)
        XCTAssertEqual(rr.riskPerUnit, 5, accuracy: 1e-9)
        XCTAssertEqual(rr.rewardPerUnit, 15, accuracy: 1e-9)
        XCTAssertEqual(rr.ratio, 3, accuracy: 1e-9)
        XCTAssertEqual(rr.breakevenWinRate, 0.25, accuracy: 1e-9)  // 1/(1+3)
    }

    func testRiskRewardShort() {
        let rr = MarketMath.riskReward(entry: 100, stop: 105, target: 90)!
        XCTAssertFalse(rr.isLong)
        XCTAssertEqual(rr.ratio, 2, accuracy: 1e-9)
    }

    func testRiskRewardRejectsBadGeometry() {
        // Long with target below entry.
        XCTAssertNil(MarketMath.riskReward(entry: 100, stop: 95, target: 98))
        // Stop equal to entry.
        XCTAssertNil(MarketMath.riskReward(entry: 100, stop: 100, target: 110))
        // Non-positive prices.
        XCTAssertNil(MarketMath.riskReward(entry: 0, stop: 95, target: 110))
    }

    // MARK: - Kelly & expectancy

    func testKellyKnownValue() {
        // W=0.6, R=2 → f* = 0.6 − 0.4/2 = 0.4
        XCTAssertEqual(MarketMath.kellyFraction(winRate: 0.6, payoff: 2), 0.4, accuracy: 1e-9)
    }

    func testKellyNegativeEdgeClampsToZero() {
        XCTAssertEqual(MarketMath.kellyFraction(winRate: 0.3, payoff: 1), 0, accuracy: 1e-9)
    }

    func testKellyInvalidInputsReturnZero() {
        XCTAssertEqual(MarketMath.kellyFraction(winRate: 0, payoff: 2), 0)
        XCTAssertEqual(MarketMath.kellyFraction(winRate: 1, payoff: 2), 0)
        XCTAssertEqual(MarketMath.kellyFraction(winRate: 0.5, payoff: 0), 0)
    }

    func testExpectancy() {
        // 50% win rate at 2R wins, 1R losses → +0.5R per trade.
        XCTAssertEqual(MarketMath.expectancy(winRate: 0.5, avgWin: 2, avgLoss: 1), 0.5, accuracy: 1e-9)
        // Negative-edge system.
        XCTAssertLessThan(MarketMath.expectancy(winRate: 0.4, avgWin: 1, avgLoss: 1), 0)
    }
}
