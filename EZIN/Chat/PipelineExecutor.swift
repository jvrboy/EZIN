import Foundation

/// Executes deterministic, inspectable analysis pipelines used by the chat orchestrator.
/// Pipelines compose production candle, indicator, council, scraper, and workspace services.
@MainActor
struct PipelineExecutor {
    struct Definition: Codable {
        let id: String
        let name: String
        let steps: [String]
        let description: String
    }

    static let definitions: [Definition] = [
        .init(id: "full_technical_analysis", name: "Full Technical Analysis", steps: ["candles", "indicators", "agents", "council", "report"], description: "Complete single-timeframe council analysis."),
        .init(id: "council_scan", name: "Council Scan", steps: ["candles", "16 agents", "weighted vote"], description: "Runs every active signal agent and reports each vote."),
        .init(id: "multi_timeframe_scan", name: "Multi-Timeframe Scan", steps: ["parallel candles", "timeframe snapshots", "confluence", "execution timing"], description: "Top-down live market analysis across the timeframe ladder."),
        .init(id: "regime_detection", name: "Regime Detection", steps: ["choppiness", "efficiency", "ADX", "volatility"], description: "Classifies trending, ranging, and volatile conditions."),
        .init(id: "anomaly_detection", name: "Anomaly Detection", steps: ["z-score", "relative volume", "spike", "flag"], description: "Flags statistically unusual price and participation behavior."),
        .init(id: "breakout_validation", name: "Breakout Validation", steps: ["Donchian", "Keltner", "Aroon", "volume confirmation"], description: "Validates channel breaks with direction and participation."),
        .init(id: "participation_check", name: "Participation Check", steps: ["relative volume", "CMF", "force index", "MFI"], description: "Checks whether money flow supports current direction."),
        .init(id: "risk_plan", name: "Risk Plan", steps: ["balance", "risk budget", "stop distance", "size"], description: "Calculates a bounded risk budget and position size."),
        .init(id: "web_research", name: "Web Research", steps: ["validate URL", "fetch", "extract", "links"], description: "Extracts readable text from a public web page."),
        .init(id: "workspace_manifest", name: "Workspace Manifest", steps: ["scan", "metadata", "sort", "report"], description: "Lists files created by assistant workflows.")
    ]

    let app: AppState

    func run(id rawID: String, args: [String: Any]) async -> String {
        let id = normalizedID(rawID)
        switch id {
        case "full_technical_analysis": return await fullTechnical(args)
        case "council_scan": return await councilScan(args)
        case "multi_timeframe_scan": return await multiTimeframe(args)
        case "regime_detection": return await focusedSnapshot(args, focus: .regime)
        case "anomaly_detection": return await focusedSnapshot(args, focus: .anomaly)
        case "breakout_validation": return await focusedSnapshot(args, focus: .breakout)
        case "participation_check": return await focusedSnapshot(args, focus: .participation)
        case "risk_plan": return riskPlan(args)
        case "web_research": return await webResearch(args)
        case "workspace_manifest": return await workspaceManifest(args)
        case "list", "": return pipelineList()
        default: return "Unknown pipeline '\(rawID)'. Use pipeline with name=list to see executable pipelines."
        }
    }

    private enum Focus { case regime, anomaly, breakout, participation }

    private func fullTechnical(_ args: [String: Any]) async -> String {
        guard let (md, ind) = await snapshot(args) else { return unavailable(args) }
        let votes = app.engine.agents.filter(\.isActive).map { $0.analyze(md, ind) }
        let decision = app.engine.council.deliberate(symbol: md.symbol, timeframe: md.timeframe, votes: votes)
        let price = md.currentPrice
        var lines = [
            "# \(DerivSymbols.display(md.symbol)) · \(md.timeframe.rawValue)",
            "Price: \(format(price)) · candles: \(md.candles.count)",
            "Regime: \(regime(ind)) · trend strength: \(format(ind.trendStrength))",
            "RSI: \(format(ind.rsi14)) · PPO hist: \(format(ind.ppoHistogram)) · Fisher: \(format(ind.fisherTransform))",
            "ADX: \(format(ind.adx)) · Aroon: \(format(ind.aroonOscillator)) · Vortex: \(format(ind.vortexPlus))/\(format(ind.vortexMinus))",
            "ATR%: \(format(ind.atrPercent)) · CHOP: \(format(ind.choppinessIndex)) · RVOL: \(format(ind.relativeVolume))"
        ]
        if let decision {
            lines.append("Council: \(directionName(decision.direction)) · confidence \(Int(decision.confidence * 100))% · consensus \(Int(decision.consensusRatio * 100))%")
        } else {
            lines.append("Council: no directional consensus")
        }
        lines.append("\n## Agent votes")
        lines.append(contentsOf: votes.map { "- \($0.agentName): \(directionName($0.direction)) \(Int($0.confidence * 100))% — \($0.rationale)" })
        return lines.joined(separator: "\n")
    }

    private func councilScan(_ args: [String: Any]) async -> String {
        guard let (md, ind) = await snapshot(args) else { return unavailable(args) }
        let votes = app.engine.agents.filter(\.isActive).map { $0.analyze(md, ind) }
        let decision = app.engine.council.deliberate(symbol: md.symbol, timeframe: md.timeframe, votes: votes)
        var lines = votes.map { "\($0.agentName) | \(directionName($0.direction)) | \(Int($0.confidence * 100))% | w \(format($0.weight)) | \($0.rationale)" }
        if let decision {
            lines.insert("COUNCIL \(directionName(decision.direction)) · confidence \(Int(decision.confidence * 100))% · consensus \(Int(decision.consensusRatio * 100))%", at: 0)
        } else {
            lines.insert("COUNCIL NEUTRAL · no weighted consensus", at: 0)
        }
        return lines.joined(separator: "\n")
    }

    private func multiTimeframe(_ args: [String: Any]) async -> String {
        let symbol = resolveSymbol(string(args, "symbol"))
        let timeframe = Timeframe(rawValue: string(args, "timeframe")) ?? .m5
        guard !symbol.isEmpty else { return "Please specify a symbol." }
        let engine = MultiTimeframeEngine(deriv: app.deriv, engine: app.engine)
        guard let report = await engine.analyze(symbol: symbol, requested: timeframe) else { return unavailable(args) }
        return report.markdown()
    }

    private func focusedSnapshot(_ args: [String: Any], focus: Focus) async -> String {
        guard let (md, ind) = await snapshot(args) else { return unavailable(args) }
        let heading = "\(DerivSymbols.display(md.symbol)) · \(md.timeframe.rawValue)"
        switch focus {
        case .regime:
            return "\(heading)\nRegime: \(regime(ind))\nCHOP \(format(ind.choppinessIndex)) · efficiency \(format(ind.efficiencyRatio)) · ADX \(format(ind.adx)) · ATR% \(format(ind.atrPercent)) · trend strength \(format(ind.trendStrength))"
        case .anomaly:
            let priceFlag = abs(ind.priceZScore) >= 2
            let volumeFlag = ind.relativeVolume >= 1.75
            let status = priceFlag || volumeFlag ? "ANOMALY DETECTED" : "No major anomaly"
            return "\(heading)\n\(status)\nPrice z-score \(format(ind.priceZScore)) · relative volume \(format(ind.relativeVolume)) · Chaikin volatility \(format(ind.chaikinVol)) · ulcer index \(format(ind.ulcerIndex))"
        case .breakout:
            let price = md.currentPrice
            let upper = price >= ind.donchianUpper || price >= ind.keltnerUpper
            let lower = price <= ind.donchianLower || price <= ind.keltnerLower
            let confirmation = ind.relativeVolume >= 1.1 && abs(ind.aroonOscillator) >= 40
            return "\(heading)\nBreakout: \(upper ? "UP" : lower ? "DOWN" : "NONE") · confirmation: \(confirmation ? "CONFIRMED" : "WEAK")\nPrice \(format(price)) · Donchian \(format(ind.donchianLower))–\(format(ind.donchianUpper)) · Aroon \(format(ind.aroonOscillator)) · RVOL \(format(ind.relativeVolume))"
        case .participation:
            let bias = ind.cmf > 0.05 && ind.forceIndex > 0 ? "BUYING" : ind.cmf < -0.05 && ind.forceIndex < 0 ? "SELLING" : "MIXED"
            return "\(heading)\nParticipation: \(bias)\nRVOL \(format(ind.relativeVolume)) · CMF \(format(ind.cmf)) · MFI \(format(ind.mfi14)) · Force Index \(format(ind.forceIndex))"
        }
    }

    private func riskPlan(_ args: [String: Any]) -> String {
        let balance = number(args, "balance")
        let riskPercent = min(5, max(0.1, number(args, "risk_percent", fallback: 1)))
        let stopDistance = number(args, "stop_distance")
        guard balance > 0, stopDistance > 0 else {
            return "Provide positive balance and stop_distance values. Optional risk_percent defaults to 1 and is capped at 5."
        }
        let budget = balance * riskPercent / 100
        let units = budget / stopDistance
        return "Risk plan\nBalance: \(format(balance))\nRisk: \(format(riskPercent))% = \(format(budget))\nStop distance: \(format(stopDistance))\nMaximum units: \(format(units))\nThis is a deterministic sizing calculation, not a trade recommendation."
    }

    private func webResearch(_ args: [String: Any]) async -> String {
        do {
            let page = try await WebScraper.shared.scrape(url: string(args, "url"), maxCharacters: Int(number(args, "max_characters", fallback: 12_000)))
            var output = "# \(page.title)\n\(page.finalURL)\n"
            if !page.description.isEmpty { output += "\n\(page.description)\n" }
            output += "\n\(page.text)"
            if !page.links.isEmpty { output += "\n\nLinks:\n" + page.links.prefix(10).map { "- \($0)" }.joined(separator: "\n") }
            return output
        } catch { return "Web research failed: \(error.localizedDescription)" }
    }

    private func workspaceManifest(_ args: [String: Any]) async -> String {
        do {
            let entries = try await AgentWorkspace.shared.list(path: string(args, "path"), recursive: true, limit: 300)
            if entries.isEmpty { return "The agent workspace is empty." }
            let total = entries.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.byteSize }
            return "Workspace: \(entries.count) items, \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))\n" +
                entries.map { "\($0.isDirectory ? "DIR " : "FILE") \($0.path) \($0.isDirectory ? "" : ByteCountFormatter.string(fromByteCount: $0.byteSize, countStyle: .file))" }.joined(separator: "\n")
        } catch { return "Workspace scan failed: \(error.localizedDescription)" }
    }

    private func snapshot(_ args: [String: Any]) async -> (MarketData, TechnicalIndicators)? {
        let symbol = resolveSymbol(string(args, "symbol"))
        let timeframe = Timeframe(rawValue: string(args, "timeframe")) ?? .m5
        guard !symbol.isEmpty else { return nil }
        do {
            let count = max(60, min(1_000, Int(number(args, "count", fallback: 300))))
            let candles = try await app.deriv.candles(symbol: symbol, timeframe: timeframe, count: count)
            guard candles.count >= 30 else { return nil }
            var md = MarketData(symbol: symbol, assetClass: DerivSymbols.assetClass(symbol), timeframe: timeframe, candles: candles)
            md.currentPrice = app.deriv.prices[symbol] ?? candles.last?.close ?? 0
            return (md, app.engine.analyzer.analyze(md))
        } catch { return nil }
    }

    private func pipelineList() -> String {
        Self.definitions.map { "\($0.id): \($0.name) — \($0.description) [\($0.steps.joined(separator: " → "))]" }.joined(separator: "\n")
    }

    private func unavailable(_ args: [String: Any]) -> String {
        let symbol = string(args, "symbol")
        return symbol.isEmpty ? "Please specify a symbol." : "Live candle data is unavailable for \(symbol). Check the Deriv connection and symbol."
    }

    private func regime(_ ind: TechnicalIndicators) -> String {
        if ind.atrPercent >= 2.5 { return "HIGH VOLATILITY" }
        if ind.choppinessIndex >= 61.8 { return "CHOPPY RANGE" }
        if ind.choppinessIndex <= 38.2 && ind.adx >= 25 { return "STRONG TREND" }
        if ind.efficiencyRatio >= 0.35 { return "DEVELOPING TREND" }
        return "MIXED"
    }

    private func normalizedID(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
    }
    private func string(_ args: [String: Any], _ key: String) -> String { args[key] as? String ?? "" }
    private func number(_ args: [String: Any], _ key: String, fallback: Double = 0) -> Double {
        if let value = args[key] as? Double { return value }
        if let value = args[key] as? Int { return Double(value) }
        return Double(string(args, key)) ?? fallback
    }
    private func resolveSymbol(_ value: String) -> String {
        if DerivSymbols.all.contains(value) { return value }
        return DerivSymbols.all.first { DerivSymbols.display($0).caseInsensitiveCompare(value) == .orderedSame }
            ?? DerivSymbols.all.first { DerivSymbols.display($0).localizedCaseInsensitiveContains(value) && !value.isEmpty }
            ?? value
    }
    private func format(_ value: Double) -> String { String(format: abs(value) >= 1_000 ? "%.2f" : "%.4f", value) }
    private func directionName(_ direction: Direction) -> String {
        switch direction {
        case .strongBullish: return "STRONG BULLISH"
        case .bullish: return "BULLISH"
        case .neutral: return "NEUTRAL"
        case .bearish: return "BEARISH"
        case .strongBearish: return "STRONG BEARISH"
        }
    }
}
