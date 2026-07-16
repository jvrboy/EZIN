import XCTest
@testable import EZIN

final class BackendAnalyticsTests: XCTestCase {
    func testMarketRegimeDetectsTrend() {
        var candles: [Candle] = []
        var price = 100.0
        for i in 0..<60 {
            price += 0.45
            candles.append(Candle(
                timestamp: Date().addingTimeInterval(-Double(60 - i) * 300),
                open: price - 0.15,
                high: price + 0.25,
                low: price - 0.30,
                close: price,
                volume: 100 + Double(i)
            ))
        }
        var md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: candles)
        md.currentPrice = price

        let regime = BackendQuantEngine.regime(md)
        XCTAssertTrue(regime.state.contains("Trending"))
        XCTAssertTrue(regime.bias.isBullish)
        XCTAssertGreaterThan(regime.persistence, 0.5)
    }

    func testMarketRegimeDetectsSqueeze() {
        let base = 100.0
        let candles = (0..<60).map { i in
            let drift = sin(Double(i) / 4.0) * 0.08
            let close = base + drift
            return Candle(
                timestamp: Date().addingTimeInterval(-Double(60 - i) * 60),
                open: close - 0.02,
                high: close + 0.04,
                low: close - 0.04,
                close: close,
                volume: 80
            )
        }
        let md = MarketData(symbol: "R_10", assetClass: .synthetic, timeframe: .m1, candles: candles, currentPrice: candles.last?.close ?? base)
        let regime = BackendQuantEngine.regime(md)
        XCTAssertGreaterThanOrEqual(regime.squeezeScore, 0)
        XCTAssertLessThanOrEqual(regime.squeezeScore, 1)
        XCTAssertFalse(regime.volatilityState.isEmpty)
    }
}
