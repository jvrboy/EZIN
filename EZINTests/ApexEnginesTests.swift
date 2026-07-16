import XCTest
@testable import EZIN

// MARK: - APEX backend engine tests

final class ApexEnginesTests: XCTestCase {

    private func trendingCandles(_ count: Int = 80, up: Bool = true) -> [Candle] {
        var candles: [Candle] = []
        var price = 100.0
        for i in 0..<count {
            price += up ? 0.4 : -0.4
            let o = price - (up ? 0.3 : -0.3)
            let c = price
            candles.append(Candle(timestamp: Date().addingTimeInterval(-Double(count - i) * 300),
                                  open: o, high: max(o, c) + 0.15, low: min(o, c) - 0.15,
                                  close: c, volume: 100))
        }
        return candles
    }

    private func marketData(_ candles: [Candle]) -> MarketData {
        var md = MarketData(symbol: "R_100", assetClass: .synthetic, timeframe: .m5, candles: candles)
        md.currentPrice = candles.last?.close ?? 0
        return md
    }

    func testPatternScanFindsEngulfing() {
        var candles = trendingCandles(40)
        // Append a bearish candle then a bigger bullish engulfing candle.
        let base = candles.last!.close
        candles.append(Candle(timestamp: Date(), open: base + 0.2, high: base + 0.3, low: base - 0.4, close: base - 0.3, volume: 100))
        candles.append(Candle(timestamp: Date(), open: base - 0.4, high: base + 0.6, low: base - 0.5, close: base + 0.5, volume: 150))
        let patterns = ApexBackend.candlePatterns(marketData(candles))
        XCTAssertTrue(patterns.contains { $0.name == "Bullish Engulfing" && $0.bullish })
    }

    func testMarketProfileProducesOrderedLevels() {
        let md = marketData(trendingCandles(90))
        let profile = ApexBackend.marketProfile(md)
        XCTAssertNotNil(profile)
        if let p = profile {
            XCTAssertGreaterThan(p.valueAreaHigh, p.pointOfControl)
            XCTAssertGreaterThan(p.pointOfControl, p.valueAreaLow)
        }
    }

    func testLiquidityMapDetectsEqualLows() {
        // Build candles with repeated swing lows at the same level (resting sell-side liquidity).
        var candles: [Candle] = []
        for i in 0..<60 {
            let phase = i % 10
            let low = (phase == 5) ? 99.0 : 100.0 + Double(phase) * 0.1
            candles.append(Candle(timestamp: Date().addingTimeInterval(Double(i) * 300),
                                  open: low + 0.5, high: low + 1.2, low: low, close: low + 0.6, volume: 100))
        }
        let map = ApexBackend.liquidityMap(marketData(candles), tolerance: 0.002)
        XCTAssertFalse(map.equalLows.isEmpty, "Expected clustered equal lows to be detected")
    }

    func testRangeForecastPositiveExpectedMove() {
        let f = ApexBackend.rangeForecast(marketData(trendingCandles(60)))
        XCTAssertNotNil(f)
        if let f {
            XCTAssertGreaterThan(f.expectedMove1, 0)
            XCTAssertGreaterThan(f.expectedMove5, f.expectedMove1)
        }
    }

    func testEntropyHigherForRandomWalkThanTrend() {
        // Trend
        let trend = trendingCandles(120).map { $0.close }
        // Deterministic "random" walk via sine mash
        var walk: [Double] = []
        var p = 100.0
        for i in 0..<120 {
            p += sin(Double(i) * 12.9898) * 0.8
            walk.append(p)
        }
        let trendER = ApexBackend.entropyAnalysis(trend)?.efficiencyRatio ?? 0
        let walkER = ApexBackend.entropyAnalysis(walk)?.efficiencyRatio ?? 1
        XCTAssertGreaterThan(trendER, walkER, "Clean trend should have a higher efficiency ratio than a noisy walk")
    }

    func testRegimeSwitchDetectsBullBias() {
        let regime = ApexBackend.regimeSwitch(trendingCandles(100, up: true).map { $0.close })
        XCTAssertNotNil(regime)
        if let r = regime { XCTAssertGreaterThanOrEqual(r.bull, r.bear) }
    }

    func testMasterConfluenceRunsAndProducesVerdict() {
        let engine = SignalEngine()
        let mc = ApexBackend.masterConfluence(marketData(trendingCandles(100)), engine: engine)
        XCTAssertFalse(mc.entries.isEmpty)
        XCTAssertGreaterThanOrEqual(mc.totalScore, -1)
        XCTAssertLessThanOrEqual(mc.totalScore, 1)
        XCTAssertGreaterThan(mc.totalConfidence, 0)
    }

    func testMasterReportIsFormattedMarkdown() {
        let report = ApexBackend.masterReport(marketData(trendingCandles(100)), symbol: "Volatility 100")
        XCTAssertTrue(report.contains("## Master Confluence"))
        XCTAssertTrue(report.contains("| Engine |"))
    }

    func testScannerRanksSymbols() {
        let md = marketData(trendingCandles(100))
        let hits = ApexBackend.scan(symbols: ["R_100", "R_75"]) { _ in md }
        XCTAssertEqual(hits.count, 2)
        XCTAssertGreaterThanOrEqual(abs(hits[0].score), abs(hits[1].score))
    }
}

// MARK: - ZipWriter tests

final class ZipWriterTests: XCTestCase {

    func testZipContainsAllEntriesAndValidCRC() {
        let entries = [
            ZipWriter.Entry(name: "a/hello.txt", data: Data("hello world".utf8)),
            ZipWriter.Entry(name: "b/data.bin", data: Data([0, 1, 2, 3, 255]))
        ]
        let zip = ZipWriter.makeZip(entries: entries)
        XCTAssertNotNil(zip)
        guard let zip else { return }
        // Signatures
        XCTAssertEqual(zip[0], 0x50); XCTAssertEqual(zip[1], 0x4B) // PK
        let bytes = [UInt8](zip)
        // EOCD signature must exist near the end
        let tail = Array(bytes.suffix(22))
        XCTAssertEqual(tail[0], 0x50); XCTAssertEqual(tail[1], 0x4B)
        XCTAssertEqual(tail[2], 0x05); XCTAssertEqual(tail[3], 0x06)
        // Entry count
        XCTAssertEqual(Int(tail[10]) | (Int(tail[11]) << 8), 2)
        // Known CRC-32 of "hello world" is 0x0D4A1185
        XCTAssertEqual(ZipWriter.crc32(Data("hello world".utf8)), 0x0D4A1185)
    }

    func testEmptyZipReturnsNil() {
        XCTAssertNil(ZipWriter.makeZip(entries: []))
        XCTAssertNil(ZipWriter.makeZip(entries: [ZipWriter.Entry(name: "   ", data: Data())]))
    }
}
