import XCTest
@testable import EZIN

/// Deterministic tests for the moving-average primitives that feed every indicator
/// and therefore every signal. Hand-checked expected values.
final class MovingAveragesTests: XCTestCase {

    func testSMAFullWindow() {
        let out = MA.sma([1, 2, 3, 4, 5], 5)
        XCTAssertEqual(out.last!, 3.0, accuracy: 1e-9)
    }

    func testSMAWarmupIsZeroThenAverages() {
        let out = MA.sma([2, 4, 6], 3)
        XCTAssertEqual(out[0], 0.0, accuracy: 1e-9) // not enough data yet
        XCTAssertEqual(out[1], 0.0, accuracy: 1e-9)
        XCTAssertEqual(out[2], 4.0, accuracy: 1e-9) // (2+4+6)/3
    }

    func testEMAOnConstantSeriesStaysConstant() {
        let out = MA.ema([5, 5, 5, 5, 5], 3)
        for v in out { XCTAssertEqual(v, 5.0, accuracy: 1e-9) }
    }

    func testEMAFirstValueSeedsWithSource() {
        let out = MA.ema([10, 20, 30], 2)
        XCTAssertEqual(out[0], 10.0, accuracy: 1e-9)
        // k = 2/(2+1) = 0.6667; out[1] = 20*k + 10*(1-k)
        let k = 2.0 / 3.0
        XCTAssertEqual(out[1], 20 * k + 10 * (1 - k), accuracy: 1e-9)
    }

    func testRMAOnConstantSeriesStaysConstant() {
        let out = MA.rma([7, 7, 7, 7], 4)
        for v in out { XCTAssertEqual(v, 7.0, accuracy: 1e-9) }
    }

    func testWMALinearWeighting() {
        // WMA of [1,2,3] len 3 = (3*3 + 2*2 + 1*1) / (3+2+1) = 14/6
        let out = MA.wma([1, 2, 3], 3)
        XCTAssertEqual(out.last!, 14.0 / 6.0, accuracy: 1e-9)
    }

    func testVWMAWeightsByVolume() {
        // Equal volume => VWMA equals SMA.
        let src = [1.0, 2.0, 3.0]
        let vol = [1.0, 1.0, 1.0]
        let out = MA.vwma(src, vol, 3)
        XCTAssertEqual(out.last!, 2.0, accuracy: 1e-9)
    }
}
