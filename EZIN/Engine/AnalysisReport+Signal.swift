import Foundation

extension AnalysisReport {
    /// Convert the merged multi-timeframe verdict into a TradingSignal for the Signals
    /// tab / bot. Returns nil for non-actionable (hold / no-consensus) verdicts.
    func toSignal(strategy: String = "MTF Confluence", expiryMinutes: Int = 30) -> TradingSignal? {
        let v = verdict
        guard v.action != .hold, v.direction != .neutral else { return nil }
        return TradingSignal(
            symbol: symbol,
            displayPair: displaySymbol,
            type: v.action,
            entry: v.entry,
            stopLoss: v.stopLoss,
            takeProfit: v.takeProfit,
            confidence: Double(v.confidence),
            strategy: strategy,
            timeframe: requestedTimeframe,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(expiryMinutes * 60))
        )
    }
}
