import Foundation

/// Pure, deterministic market math shared by the chat tool pack and unit tests.
/// No AppState / networking dependencies — everything here is trivially testable.
enum MarketMath {

    // MARK: - Fibonacci retracements & extensions

    struct FibLevels {
        let high: Double
        let low: Double
        let isUpLeg: Bool
        let retracements: [(ratio: Double, price: Double)]
        let extensions: [(ratio: Double, price: Double)]
    }

    /// Standard retracement (23.6–78.6%) and extension (127.2–200%) levels for a swing leg.
    /// For an up-leg retracements descend from the high; for a down-leg they ascend from the low.
    static func fibonacci(high: Double, low: Double, isUpLeg: Bool) -> FibLevels {
        let range = high - low
        let retRatios: [Double] = [0.236, 0.382, 0.5, 0.618, 0.786]
        let extRatios: [Double] = [1.272, 1.414, 1.618, 2.0]
        let retracements: [(ratio: Double, price: Double)] = retRatios.map {
            (ratio: $0, price: isUpLeg ? high - range * $0 : low + range * $0)
        }
        let extensions: [(ratio: Double, price: Double)] = extRatios.map {
            (ratio: $0, price: isUpLeg ? low + range * $0 : high - range * $0)
        }
        return FibLevels(high: high, low: low, isUpLeg: isUpLeg,
                         retracements: retracements, extensions: extensions)
    }

    // MARK: - Pivot levels (classic / Woodie / Camarilla)

    struct PivotSet {
        let pivot: Double
        let r1: Double, r2: Double, r3: Double
        let s1: Double, s2: Double, s3: Double
    }

    static func classicPivots(high h: Double, low l: Double, close c: Double) -> PivotSet {
        let p = (h + l + c) / 3
        return PivotSet(pivot: p,
                        r1: 2 * p - l, r2: p + (h - l), r3: h + 2 * (p - l),
                        s1: 2 * p - h, s2: p - (h - l), s3: l - 2 * (h - p))
    }

    static func woodiePivots(high h: Double, low l: Double, close c: Double) -> PivotSet {
        let p = (h + l + 2 * c) / 4
        return PivotSet(pivot: p,
                        r1: 2 * p - l, r2: p + (h - l), r3: h + 2 * (p - l),
                        s1: 2 * p - h, s2: p - (h - l), s3: l - 2 * (h - p))
    }

    static func camarillaPivots(high h: Double, low l: Double, close c: Double) -> PivotSet {
        let range = h - l
        return PivotSet(pivot: (h + l + c) / 3,
                        r1: c + range * 1.1 / 12, r2: c + range * 1.1 / 6, r3: c + range * 1.1 / 4,
                        s1: c - range * 1.1 / 12, s2: c - range * 1.1 / 6, s3: c - range * 1.1 / 4)
    }

    // MARK: - Win/loss streak statistics

    struct StreakStats {
        /// Positive = current up streak length; negative = current down streak length.
        let currentStreak: Int
        let maxUpStreak: Int
        let maxDownStreak: Int
        /// P(up bar | previous bar up), 0…1. NaN-free: 0 when no samples.
        let upAfterUp: Double
        /// P(up bar | previous bar down), 0…1.
        let upAfterDown: Double
        let upBars: Int
        let downBars: Int
    }

    static func streaks(closes: [Double]) -> StreakStats {
        var dirs: [Int] = []          // +1 up, -1 down (flat bars skipped)
        for i in 1..<max(closes.count, 1) {
            let d = closes[i] - closes[i - 1]
            if d > 0 { dirs.append(1) } else if d < 0 { dirs.append(-1) }
        }
        var current = 0, maxUp = 0, maxDown = 0
        var upUp = 0, upUpTotal = 0, upDown = 0, upDownTotal = 0
        var ups = 0, downs = 0
        for (i, d) in dirs.enumerated() {
            if d == 1 { ups += 1 } else { downs += 1 }
            if i > 0 {
                if dirs[i - 1] == 1 { upUpTotal += 1; if d == 1 { upUp += 1 } }
                else { upDownTotal += 1; if d == 1 { upDown += 1 } }
            }
            if d == 1 { current = current > 0 ? current + 1 : 1 }
            else { current = current < 0 ? current - 1 : -1 }
            maxUp = max(maxUp, current)
            maxDown = min(maxDown, current)
        }
        return StreakStats(currentStreak: current,
                           maxUpStreak: maxUp,
                           maxDownStreak: -maxDown,
                           upAfterUp: upUpTotal > 0 ? Double(upUp) / Double(upUpTotal) : 0,
                           upAfterDown: upDownTotal > 0 ? Double(upDown) / Double(upDownTotal) : 0,
                           upBars: ups, downBars: downs)
    }

    // MARK: - Risk / reward & position math

    struct RiskReward {
        let riskPerUnit: Double
        let rewardPerUnit: Double
        let ratio: Double            // reward ÷ risk
        let breakevenWinRate: Double // 0…1 win rate needed for expectancy = 0
        let isLong: Bool
    }

    /// Returns nil when the geometry is invalid (stop on the wrong side, or target not
    /// beyond entry in the trade direction).
    static func riskReward(entry: Double, stop: Double, target: Double) -> RiskReward? {
        guard entry > 0, stop > 0, target > 0, entry != stop else { return nil }
        let isLong = stop < entry
        let risk = abs(entry - stop)
        let reward = isLong ? target - entry : entry - target
        guard reward > 0 else { return nil }
        let ratio = reward / risk
        return RiskReward(riskPerUnit: risk, rewardPerUnit: reward, ratio: ratio,
                          breakevenWinRate: 1 / (1 + ratio), isLong: isLong)
    }

    /// Kelly fraction f* = W − (1 − W) / R. Clamped to 0…1; 0 when the edge is negative.
    static func kellyFraction(winRate: Double, payoff: Double) -> Double {
        guard payoff > 0, winRate > 0, winRate < 1 else { return 0 }
        let f = winRate - (1 - winRate) / payoff
        return min(max(f, 0), 1)
    }

    /// Expectancy per trade in R-multiples: W·avgWin − (1−W)·avgLoss.
    static func expectancy(winRate: Double, avgWin: Double, avgLoss: Double) -> Double {
        winRate * avgWin - (1 - winRate) * abs(avgLoss)
    }
}
