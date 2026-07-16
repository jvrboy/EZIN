import Foundation

struct SignalPerformanceSnapshot {
    let sampleSize: Int
    let activeCount: Int
    let resolvedCount: Int
    let winRate: Double
    let expectancy: Double
    let averageHoldMinutes: Double
    let averageMaxDrawdown: Double
    let averageMaxRunup: Double
    let recentStreak: Int
    let bestSymbol: String?
    let worstSymbol: String?
}

@MainActor
extension SignalPerformanceStore {
    func snapshot(symbol: String? = nil, timeframe: Timeframe? = nil) -> SignalPerformanceSnapshot {
        let filtered = trackedSignals.filter { tracked in
            let symbolMatch = symbol == nil || tracked.signal.symbol == symbol
            let timeframeMatch = timeframe == nil || tracked.signal.timeframe == timeframe
            return symbolMatch && timeframeMatch
        }
        let active = filtered.filter { $0.status == .active }
        let resolved = filtered.filter { $0.status != .active }
        let winRate = resolved.isEmpty ? 0 : Double(resolved.filter { $0.isWin }.count) / Double(resolved.count)
        let expectancy = resolved.isEmpty ? 0 : resolved.map { $0.floatingPnL }.reduce(0, +) / Double(resolved.count)
        let avgHold = resolved.compactMap { $0.holdingTime }.isEmpty ? 0 : resolved.compactMap { $0.holdingTime }.reduce(0, +) / Double(resolved.compactMap { $0.holdingTime }.count) / 60
        let avgDD = resolved.isEmpty ? 0 : resolved.map { $0.maxDrawdown }.reduce(0, +) / Double(resolved.count)
        let avgRunup = resolved.isEmpty ? 0 : resolved.map { $0.maxRunup }.reduce(0, +) / Double(resolved.count)

        var streak = 0
        for signal in resolved.sorted(by: { ($0.exitTime ?? .distantPast) > ($1.exitTime ?? .distantPast) }) {
            if signal.isWin {
                if streak >= 0 { streak += 1 } else { break }
            } else {
                if streak <= 0 { streak -= 1 } else { break }
            }
        }

        let grouped = Dictionary(grouping: resolved, by: { $0.signal.symbol })
        let symbolStats = grouped.mapValues { group -> (winRate: Double, count: Int) in
            let wr = group.isEmpty ? 0 : Double(group.filter { $0.isWin }.count) / Double(group.count)
            return (wr, group.count)
        }.filter { $0.value.count >= 2 }

        let best = symbolStats.max { lhs, rhs in
            lhs.value.winRate == rhs.value.winRate ? lhs.value.count < rhs.value.count : lhs.value.winRate < rhs.value.winRate
        }?.key
        let worst = symbolStats.min { lhs, rhs in
            lhs.value.winRate == rhs.value.winRate ? lhs.value.count < rhs.value.count : lhs.value.winRate < rhs.value.winRate
        }?.key

        return SignalPerformanceSnapshot(
            sampleSize: filtered.count,
            activeCount: active.count,
            resolvedCount: resolved.count,
            winRate: winRate,
            expectancy: expectancy,
            averageHoldMinutes: avgHold,
            averageMaxDrawdown: avgDD,
            averageMaxRunup: avgRunup,
            recentStreak: streak,
            bestSymbol: best,
            worstSymbol: worst
        )
    }

    func formattedSnapshot(symbol: String? = nil, timeframe: Timeframe? = nil) -> String {
        let snap = snapshot(symbol: symbol, timeframe: timeframe)
        var scope: [String] = []
        if let symbol, !symbol.isEmpty { scope.append(DerivSymbols.display(symbol)) }
        if let timeframe { scope.append(timeframe.rawValue) }
        let title = scope.isEmpty ? "all tracked signals" : scope.joined(separator: " · ")
        let streakText: String
        if snap.recentStreak > 0 {
            streakText = "\(snap.recentStreak)-signal winning streak"
        } else if snap.recentStreak < 0 {
            streakText = "\(abs(snap.recentStreak))-signal losing streak"
        } else {
            streakText = "no streak yet"
        }

        var lines: [String] = [
            "## Performance Snapshot",
            "**Scope:** \(title)",
            "- Sample size: \(snap.sampleSize) tracked · active \(snap.activeCount) · resolved \(snap.resolvedCount)",
            "- Win rate: \(pct(snap.winRate)) · expectancy: \(num(snap.expectancy))",
            "- Avg hold: \(num(snap.averageHoldMinutes)) min · avg max drawdown: \(num(snap.averageMaxDrawdown)) · avg max run-up: \(num(snap.averageMaxRunup))",
            "- Recent streak: \(streakText)"
        ]
        if let best = snap.bestSymbol {
            lines.append("- Best symbol: \(DerivSymbols.display(best))")
        }
        if let worst = snap.worstSymbol, worst != snap.bestSymbol {
            lines.append("- Weakest symbol: \(DerivSymbols.display(worst))")
        }
        let recs = recommendations()
        if !recs.isEmpty {
            lines.append("")
            lines.append("**Recommendations**")
            lines.append(contentsOf: recs.prefix(3).map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    func exportTrackedSignalsCSV(symbol: String? = nil, timeframe: Timeframe? = nil) -> String {
        let rows = trackedSignals.filter { tracked in
            let symbolMatch = symbol == nil || tracked.signal.symbol == symbol
            let timeframeMatch = timeframe == nil || tracked.signal.timeframe == timeframe
            return symbolMatch && timeframeMatch
        }
        var csv = "id,symbol,displayPair,timeframe,type,status,confidence,entryPrice,lastPrice,exitPrice,floatingPnL,maxDrawdown,maxRunup,createdAt,exitTime\n"
        let iso = ISO8601DateFormatter()
        for row in rows {
            let values: [String] = [
                row.id.uuidString,
                row.signal.symbol,
                row.signal.displayPair,
                row.signal.timeframe.rawValue,
                row.signal.type.rawValue,
                row.status.rawValue,
                String(Int(row.signal.confidence)),
                num(row.entryPrice),
                num(row.lastPrice ?? 0),
                num(row.exitPrice ?? 0),
                num(row.floatingPnL),
                num(row.maxDrawdown),
                num(row.maxRunup),
                iso.string(from: row.signal.createdAt),
                row.exitTime.map { iso.string(from: $0) } ?? ""
            ]
            csv += values.map(csvEscape).joined(separator: ",") + "\n"
        }
        return csv
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func num(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
