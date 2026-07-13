import Foundation

// MARK: - Timeframe ordering & multi-timeframe ladder helpers
//
// The deep analysis engine walks the FULL timeframe ladder (not just the one the
// user asked for). These helpers give a stable ordering, higher/lower navigation,
// and a per-timeframe weight so that higher timeframes dominate the final bias.

extension Timeframe {
    /// Fast → slow ordering used everywhere in the multi-timeframe engine.
    static let ladder: [Timeframe] = [.m1, .m5, .m15, .m30, .h1, .h4, .d1]

    /// Position on the ladder (0 = fastest).
    var ladderIndex: Int { Timeframe.ladder.firstIndex(of: self) ?? 0 }

    /// Human label, e.g. "5-minute".
    var longLabel: String {
        switch self {
        case .m1: return "1-minute"
        case .m5: return "5-minute"
        case .m15: return "15-minute"
        case .m30: return "30-minute"
        case .h1: return "1-hour"
        case .h4: return "4-hour"
        case .d1: return "daily"
        }
    }

    /// Confluence weight — higher timeframes carry more authority over the bias.
    var confluenceWeight: Double {
        switch self {
        case .m1: return 0.6
        case .m5: return 0.9
        case .m15: return 1.1
        case .m30: return 1.3
        case .h1: return 1.6
        case .h4: return 2.0
        case .d1: return 2.4
        }
    }

    /// The timeframes to analyse when the user asks about `self`.
    /// Always includes the full ladder up to and including the requested timeframe
    /// plus the two next-higher timeframes for top-down context.
    var analysisSet: [Timeframe] {
        let all = Timeframe.ladder
        let upto = all.filter { $0.ladderIndex <= self.ladderIndex }
        let higher = all.filter { $0.ladderIndex > self.ladderIndex }.prefix(2)
        var set = upto + higher
        if !set.contains(.m1) { set.insert(.m1, at: 0) }   // 1m execution read is always required
        // de-dup, keep ladder order
        var seen = Set<Timeframe>()
        return Timeframe.ladder.filter { set.contains($0) && seen.insert($0).inserted }
    }

    var next: Timeframe? {
        let i = ladderIndex + 1
        return i < Timeframe.ladder.count ? Timeframe.ladder[i] : nil
    }
    var previous: Timeframe? {
        let i = ladderIndex - 1
        return i >= 0 ? Timeframe.ladder[i] : nil
    }
}
