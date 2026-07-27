import XCTest
@testable import EZIN

final class SafetyAndMicrostructureTests: XCTestCase {
    func testVolumeProfileHonorsConfiguredValueArea() {
        let highs = (0..<40).map { 100.0 + Double($0 % 5) }
        let lows = highs.map { $0 - 0.8 }
        let closes = highs.map { $0 - 0.4 }
        let volume = (0..<40).map { _ in 100.0 }

        let narrow = Microstructure.volumeProfile(
            high: highs, low: lows, close: closes, volume: volume,
            bins: 24, valueArea: 0.60
        )
        let wide = Microstructure.volumeProfile(
            high: highs, low: lows, close: closes, volume: volume,
            bins: 24, valueArea: 0.80
        )

        XCTAssertNotNil(narrow)
        XCTAssertNotNil(wide)
        XCTAssertLessThanOrEqual(narrow!.valueAreaWidth, wide!.valueAreaWidth)
    }

    func testBotConfigDefaultsToPaperAndSupportsLegacyDecode() throws {
        let legacy: [String: Any] = [
            "fixedLotSize": 1.0,
            "multiplier": 100,
            "instruments": ["R_100"],
            "maxOpenPositions": 2,
            "stopMode": "Bot Choice",
            "stopLossValue": 50.0,
            "takeProfitValue": 100.0,
            "minConfidence": 0.7,
            "currency": "USD"
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let config = try JSONDecoder().decode(BotConfig.self, from: data)
        XCTAssertEqual(config.executionMode, .paper)
        XCTAssertTrue(config.requireOrderPreview)
        XCTAssertEqual(config.dailyTradeLimit, 10)
    }

    func testFormattingHelpersReturnValues() {
        XCTAssertEqual(BacktestingFramework.fmt(1.234, 2), "1.23")
    }

    func testTradingSignalRiskRewardIsPositiveForValidStops() {
        let signal = TradingSignal(
            symbol: "R_100", displayPair: "Volatility 100", type: .buy,
            entry: 100, stopLoss: 98, takeProfit: 104, confidence: 80,
            strategy: "test", timeframe: .m5, createdAt: Date(),
            expiresAt: Date().addingTimeInterval(300)
        )
        XCTAssertEqual(signal.riskReward, 2, accuracy: 0.0001)
    }
}
