import Foundation

/// Session-aware scanning policy.
///
/// Requirements encoded here:
///   • Synthetics trade 24/7 → always scanned aggressively, many signals around the clock.
///   • Forex & crypto are scanned all day but MUCH more aggressively during the quiet
///     overnight window 23:00–05:00 SAST (Africa/Johannesburg), when the market is
///     "asleep" (little manipulation) — the ideal time to analyse.
enum TradingSession {
    static let sast = TimeZone(identifier: "Africa/Johannesburg") ?? TimeZone(secondsFromGMT: 2 * 3600)!

    /// Current hour (0–23) in SAST.
    static func sastHour(_ date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = sast
        return cal.component(.hour, from: date)
    }

    /// The quiet overnight aggressive window: 23:00 → 05:00 SAST.
    static func isAfterHours(_ date: Date = Date()) -> Bool {
        let h = sastHour(date)
        return h >= 23 || h < 5
    }

    struct Policy {
        let scanSeconds: UInt64      // cadence for this asset class right now
        let minConfidence: Double    // 0…100 confidence gate for emitting a signal
        let baseTimeframe: Timeframe // timeframe the MTF scan is anchored on
        let aggressive: Bool
    }

    /// Decide how aggressively to scan a given asset class right now.
    static func policy(for asset: AssetClass, date: Date = Date()) -> Policy {
        switch asset {
        case .synthetic:
            // 24/7 aggressive — fast cadence, permissive gate ⇒ many signals around the clock.
            return Policy(scanSeconds: 8, minConfidence: 58, baseTimeframe: .m5, aggressive: true)
        case .forex, .crypto, .commodity, .index:
            if isAfterHours(date) {
                // Quiet overnight window — hunt hard.
                return Policy(scanSeconds: 10, minConfidence: 60, baseTimeframe: .m5, aggressive: true)
            } else {
                // Daytime — still active, but more selective (fewer, higher-quality signals).
                return Policy(scanSeconds: 25, minConfidence: 70, baseTimeframe: .m15, aggressive: false)
            }
        }
    }

    /// Global fastest cadence across all currently-scanned asset classes.
    static func globalScanSeconds(for symbols: [String], date: Date = Date()) -> UInt64 {
        let policies = Set(symbols.map { DerivSymbols.assetClass($0) }).map { policy(for: $0, date: date).scanSeconds }
        return policies.min() ?? 12
    }

    /// Short label for logs / UI.
    static func label(_ date: Date = Date()) -> String {
        isAfterHours(date) ? "Overnight (aggressive FX/crypto)" : "Day session"
    }
}
