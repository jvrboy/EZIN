import Foundation

extension AnalysisReport {

    private func fmt(_ v: Double) -> String { v > 100 ? String(format: "%.2f", v) : String(format: "%.5f", v) }
    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func arrow(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "▲▲"
        case .bullish: return "▲"
        case .neutral: return "▬"
        case .bearish: return "▼"
        case .strongBearish: return "▼▼"
        }
    }

    /// A professional, fully structured Markdown report. This is what the chat tool
    /// feeds back to the LLM (and can be rendered directly). Clean headings, tables
    /// and ordered reasoning — no stray formatting artifacts.
    func markdown() -> String {
        var m = ""
        m += "# \(displaySymbol) — Deep Multi-Timeframe Analysis\n"
        m += "_Requested timeframe: **\(requestedTimeframe.longLabel)** · \(String(describing: assetClass)) · \(perTimeframe.count) timeframes analysed_\n\n"

        // Verdict banner first.
        m += "## Final Verdict\n"
        m += "**\(verdict.action.rawValue.replacingOccurrences(of: "_", with: " "))** \(arrow(verdict.direction)) · Confidence **\(verdict.confidence)%**\n\n"
        m += "| Field | Value |\n|---|---|\n"
        m += "| Entry | \(fmt(verdict.entry)) |\n"
        m += "| Stop Loss | \(fmt(verdict.stopLoss)) |\n"
        m += "| Take Profit | \(fmt(verdict.takeProfit)) |\n"
        m += "| Risk : Reward | 1 : \(String(format: "%.2f", verdict.riskReward)) |\n\n"

        // Multi-timeframe table.
        m += "## Timeframe Ladder\n"
        m += "| TF | Bias | Momentum | Trend | Volume | Regime | Order Flow | Consensus |\n"
        m += "|---|---|---|---|---|---|---|---|\n"
        for s in perTimeframe {
            m += "| \(s.timeframe.rawValue) | \(arrow(s.direction)) \(directionWord(s.direction)) | \(s.momentumLabel) | \(Int(s.trendStrength)) | \(s.volumeBiasText) | \(s.regime.rawValue) | \(directionWord(s.orderFlowBias)) | \(pct(s.consensus)) |\n"
        }
        m += "\n"

        // Confluence.
        m += "## Cross-Timeframe Confluence\n"
        m += "- Alignment score: **\(String(format: "%.2f", confluence.alignmentScore))** (−1 bearish … +1 bullish)\n"
        m += "- Dominant direction: **\(directionWord(confluence.dominantDirection))** · agreement **\(confluence.agreementPct)%**\n"
        for n in confluence.notes { m += "- \(n)\n" }
        m += "\n"

        // 1-minute execution timing.
        m += "## 1-Minute Execution Timing\n"
        m += "\(executionRead.text)\n"
        m += "- Immediate resistance: \(fmt(executionRead.immediateLevelAbove)) · immediate support: \(fmt(executionRead.immediateLevelBelow))\n\n"

        // Requested timeframe deep dive.
        let f = requestedFocus
        m += "## \(requestedTimeframe.longLabel.capitalized) Deep Dive (requested)\n"
        m += "- Direction: **\(directionWord(f.direction))** (\(String(describing: f.strength))) · council confidence \(pct(f.councilConfidence))\n"
        m += "- Momentum: \(f.momentumLabel) · trend strength \(Int(f.trendStrength)) · speed \(String(format: "%.3f%%", f.speed)) (accel \(String(format: "%.3f", f.accel)))\n"
        m += "- Volume: \(f.volumeBiasText) · volatility \(f.regime.rawValue) (realized \(String(format: "%.4f", f.realizedVol)))\n"
        m += "- Key levels — support \(fmt(f.support)) · resistance \(fmt(f.resistance)) · POC \(fmt(f.poc)) · value area \(fmt(f.valueAreaLow))–\(fmt(f.valueAreaHigh))\n"
        m += "- Order flow: \(directionWord(f.orderFlowBias)) · net aggression \(String(format: "%.2f", f.netAggressiveVolume)) · buy-bar ratio \(Int(f.tradeDirectionRatio * 100))%\n"
        if !f.topVotes.isEmpty {
            m += "- Top agent reads: " + f.topVotes.map { "\($0.agentName) (\($0.rationale))" }.joined(separator: "; ") + "\n"
        }
        m += "\n"

        // Reasoning + warnings.
        m += "## How the Decision Was Reached\n"
        for (i, r) in verdict.rationale.enumerated() { m += "\(i + 1). \(r)\n" }
        if !verdict.warnings.isEmpty {
            m += "\n## Risk Notes\n"
            for w in verdict.warnings { m += "- ⚠︎ \(w)\n" }
        }
        m += "\n_Not financial advice. Manage risk on every trade._"
        return m
    }

    /// Compact one-line summary for logs / signal tags.
    func summaryLine() -> String {
        "\(displaySymbol) [\(requestedTimeframe.rawValue)] \(verdict.action.rawValue) \(verdict.confidence)% · align \(String(format: "%.2f", confluence.alignmentScore)) · \(confluence.agreementPct)% agree"
    }

    private func directionWord(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "strong buy"
        case .bullish: return "bullish"
        case .neutral: return "neutral"
        case .bearish: return "bearish"
        case .strongBearish: return "strong sell"
        }
    }
}
