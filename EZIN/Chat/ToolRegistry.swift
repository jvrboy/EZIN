import Foundation

/// Executes the in-app + MCP tools the chat agent can call.
@MainActor
struct ToolRegistry {
    let app: AppState

    func run(_ name: String, args: [String: Any]) async -> String {
        switch name {
        case "analyze":        return await analyze(args)
        case "signals":        return signals()
        case "price":          return price(args)
        case "instruments":    return instruments(args)
        case "history":        return history()
        case "place_trade":    return await placeTrade(args)
        case "mcp":            return await mcp(args)
        case "signal_performance": return signalPerformance(args)
        case "agent_leaderboard":  return agentLeaderboard()
        case "inject_news":        return injectNews(args)
        case "create_artifact":    return createArtifact(args)
        case "create_song":        return createSong(args)
        case "brain_insights":     return brainInsights()
        case "brain_report":       return brainReport()
        case "ultra_confirm":      return ultraConfirmation(args)
        case "quant_analysis":     return quantitativeAnalysis(args)
        case "backtest":           return backtest(args)
        case "risk_plan":          return riskPlan(args)
        default:               return "Unknown tool: \(name)"
        }
    }

    // MARK: helpers
    private func str(_ a: [String: Any], _ k: String) -> String { (a[k] as? String) ?? "" }

    private func resolveSymbol(_ s: String) -> String {
        if DerivSymbols.all.contains(s) { return s }
        if let m = DerivSymbols.all.first(where: { DerivSymbols.display($0).lowercased() == s.lowercased() }) { return m }
        if let m = DerivSymbols.all.first(where: { DerivSymbols.display($0).lowercased().contains(s.lowercased()) && !s.isEmpty }) { return m }
        return s
    }

    private func resolveTF(_ s: String) -> Timeframe { Timeframe(rawValue: s) ?? .m5 }

    // MARK: tools

    /// Deep multi-timeframe analysis. Never a single-timeframe snapshot: this walks the
    /// full timeframe ladder, deep-analyses each timeframe (direction, bias, momentum,
    /// volume, levels, order flow, volatility regime, speed), reads the 1-minute
    /// execution timing, computes cross-timeframe confluence, deep-dives the requested
    /// timeframe, then merges everything into a single buy/sell verdict.
    private func analyze(_ args: [String: Any]) async -> String {
        let sym = resolveSymbol(str(args, "symbol"))
        let tf = resolveTF(str(args, "timeframe"))
        guard !sym.isEmpty else { return "Please specify a symbol." }
        let mtf = MultiTimeframeEngine(deriv: app.deriv, engine: app.engine)
        guard let report = await mtf.analyze(symbol: sym, requested: tf) else {
            return "No market data available for \(DerivSymbols.display(sym)). Open it on the Chart tab to subscribe, or check the connection."
        }
        return report.markdown()
    }

    private func signals() -> String {
        guard !app.signals.isEmpty else { return "No live signals right now." }
        return app.signals.prefix(8).map {
            "\($0.displayPair): \($0.isBuy ? "BUY" : "SELL") \(Int($0.confidence))% (\($0.strategy))"
        }.joined(separator: "\n")
    }

    private func price(_ args: [String: Any]) -> String {
        let sym = resolveSymbol(str(args, "symbol"))
        if let p = app.deriv.prices[sym] { return "\(DerivSymbols.display(sym)) = \(p)" }
        return "No live price for \(DerivSymbols.display(sym)) yet (open it on the Chart tab to subscribe)."
    }

    private func instruments(_ args: [String: Any]) -> String {
        let q = str(args, "query").lowercased()
        let matches = DerivSymbols.all.filter { q.isEmpty || DerivSymbols.display($0).lowercased().contains(q) || $0.lowercased().contains(q) }
        guard !matches.isEmpty else { return "No instruments match '\(q)'." }
        return matches.prefix(25).map { "\(DerivSymbols.display($0)) [\($0)]" }.joined(separator: "\n")
    }

    private func history() -> String {
        if app.deriv.authorized, !app.history.isEmpty {
            let net = app.history.reduce(0) { $0 + $1.profit }
            return "\(app.history.count) closed trades, net P&L \(String(format: "%.2f", net)) \(app.deriv.currency)."
        }
        let sigs = SignalHistoryStore.shared.signals
        guard !sigs.isEmpty else { return "No trade or signal history yet." }
        return "\(sigs.count) generated signals logged. Recent: " + sigs.prefix(5).map { "\($0.displayPair) \($0.isBuy ? "BUY" : "SELL")" }.joined(separator: ", ")
    }

    private func placeTrade(_ args: [String: Any]) async -> String {
        guard ChatConfigStore.shared.config.allowTrading else {
            return "Trading from chat is disabled. Enable 'Allow trading from chat' in Chat settings first."
        }
        guard app.deriv.authorized else {
            return "Not authorized — add your Deriv API token in Settings to place real trades."
        }
        let sym = resolveSymbol(str(args, "symbol"))
        let dir = str(args, "direction").lowercased()
        let up = dir.contains("buy") || dir.contains("up") || dir.contains("long")
        let stake = (args["stake"] as? Double) ?? Double(str(args, "stake")) ?? app.botConfig.config.fixedLotSize
        do {
            let prop = try await app.deriv.proposal(symbol: sym, up: up, stake: stake,
                                                    multiplier: app.botConfig.config.multiplier,
                                                    currency: app.deriv.currency, stopLoss: nil, takeProfit: nil)
            let cid = try await app.deriv.buy(proposalId: prop.id, price: prop.price)
            return "Placed \(up ? "BUY" : "SELL") on \(DerivSymbols.display(sym)) stake \(stake) \(app.deriv.currency). Contract #\(cid)."
        } catch {
            return "Trade failed: \(error.localizedDescription)"
        }
    }

    private func mcp(_ args: [String: Any]) async -> String {
        let server = str(args, "server")
        let tool = str(args, "tool")
        let toolArgs = (args["args"] as? [String: Any]) ?? [:]
        guard let conn = MCPStore.shared.byServerName(server) else {
            return "No enabled MCP connector named '\(server)'. Add or enable one in Settings → MCP Connectors."
        }
        do { return try await MCPClient(connector: conn).callTool(tool, args: toolArgs) }
        catch { return "MCP call failed: \(error.localizedDescription)" }
    }

    // MARK: - Signal Performance

    private func signalPerformance(_ args: [String: Any]) -> String {
        let sym = resolveSymbol(str(args, "symbol"))
        if !sym.isEmpty {
            let signals = app.signalPerformance.signalsForSymbol(sym)
            let wr = app.signalPerformance.winRate(for: sym)
            return "\(DerivSymbols.display(sym)): \(signals.count) tracked, \(Int(wr * 100))% win rate."
        }
        let overallWR = Int(app.signalPerformance.overallWinRate * 100)
        let recs = app.signalPerformance.recommendations()
        var result = "Overall Signal Performance: \(overallWR)% win rate.\n"
        result += "Active: \(app.signalPerformance.activeSignals().count) | Resolved: \(app.signalPerformance.resolvedSignals().count)\n"
        result += "Avg R:R: \(String(format: "%.1f", app.signalPerformance.averageRR))\n"
        if !recs.isEmpty {
            result += "\nInsights:\n" + recs.map { "• \($0)" }.joined(separator: "\n")
        }
        return result
    }

    // MARK: - Agent Leaderboard

    private func agentLeaderboard() -> String {
        let board = app.engine.agentLeaderboard()
        guard !board.isEmpty else { return "No agent performance data yet. Signals need to resolve first." }
        return board.map { (name, accuracy, total) in
            "• \(name): \(Int(accuracy * 100))% (\(total) signals)"
        }.joined(separator: "\n")
    }

    // MARK: - News Injection

    private func injectNews(_ args: [String: Any]) -> String {
        let headline = str(args, "headline")
        let impactStr = str(args, "impact").lowercased()
        let confidence = (args["confidence"] as? Double) ?? Double(str(args, "confidence")) ?? 0.7

        let impact: NewsReactiveAgent.NewsEvent.Impact
        switch impactStr {
        case "bullish", "positive", "up": impact = .bullish
        case "bearish", "negative", "down": impact = .bearish
        default: impact = .neutral
        }

        NewsReactiveAgent.injectEvent(headline: headline, impact: impact, confidence: confidence)
        return "Injected news event: '\(headline.prefix(60))' (\(impactStr), \(Int(confidence * 100))% confidence)."
    }

    // MARK: - Artifact Creation

    private func createArtifact(_ args: [String: Any]) -> String {
        guard let kindStr = args["kind"] as? String else { return "Missing 'kind' parameter." }
        let name = (args["name"] as? String) ?? "artifact"
        let content = (args["content"] as? String) ?? (args["spec"] as? String) ?? ""

        let kind: ArtifactsCreator.ArtifactSpec.Kind
        switch kindStr.lowercased() {
        case "wav", "audio": kind = .wav
        case "midi": kind = .midi
        case "csv": kind = .csv
        case "json": kind = .json
        case "html": kind = .html
        case "text", "txt": kind = .text
        case "md", "markdown": kind = .markdown
        case "py", "python": kind = .python
        case "js", "javascript": kind = .javascript
        case "swift": kind = .swift
        case "zip": kind = .zip
        case "app", "prototype", "appprototype": kind = .appPrototype
        default: return "Unknown artifact kind: '\(kindStr)'. Supported: wav, midi, csv, json, html, txt, md, py, js, swift, zip, appPrototype."
        }

        let spec = ArtifactsCreator.ArtifactSpec(kind: kind, name: name, content: content)
        guard let artifact = ArtifactsCreator.create(spec: spec) else {
            return "Failed to create artifact."
        }
        return "Created \(artifact.name) (\(artifact.sizeDisplay)). Tap the chip to download."
    }

    // MARK: - Song / Audio Creation

    private func createSong(_ args: [String: Any]) -> String {
        let prompt = (args["prompt"] as? String) ?? ""
        let name = (args["name"] as? String) ?? "song"
        let format = (args["format"] as? String ?? "wav").lowercased()
        let tempo = (args["tempo"] as? Double).map { UInt16($0) } ?? 120

        let noteDesc = promptToNotes(prompt)

        let artifact: Artifact?
        if format == "midi" || format == "mid" {
            guard let data = AudioGenerationService.generateMIDI(from: noteDesc, tempoBPM: tempo) else {
                return "Failed to generate MIDI."
            }
            artifact = saveAudioArtifact(data: data, name: name, ext: "mid")
        } else {
            guard let data = AudioGenerationService.generateWAV(from: noteDesc) else {
                return "Failed to generate WAV."
            }
            artifact = saveAudioArtifact(data: data, name: name, ext: "wav")
        }

        guard let art = artifact else { return "Failed to save audio file." }
        return "Created \(art.name) (\(art.sizeDisplay)) from: '\(prompt.prefix(60))'."
    }

    private func saveAudioArtifact(data: Data, name: String, ext: String) -> Artifact? {
        let dir = FileStore.shared.artifactsDir
        let fileName = "\(name).\(ext)"
        let url = FileStore.shared.saveData(data, name: fileName, in: dir)
        let relPath = FileStore.shared.relativePath(url)
        let artifact = Artifact(name: fileName, relativePath: relPath, kind: ext, byteSize: Int64(data.count))
        ArtifactStore.shared.add(artifact)
        return artifact
    }

    private func promptToNotes(_ prompt: String) -> String {
        let p = prompt.lowercased()
        if p.contains("major chord") || p.contains("happy") {
            let root = extractNote(from: p) ?? "C4"
            return chordPattern(root: root, minor: false)
        }
        if p.contains("minor chord") || p.contains("sad") {
            let root = extractNote(from: p) ?? "A3"
            return chordPattern(root: root, minor: true)
        }
        if p.contains("scale") || p.contains("ascending") {
            return "\(extractNote(from: p) ?? "C4") 0.5s\nD4 0.5s\nE4 0.5s\nF4 0.5s\nG4 0.5s\nA4 0.5s\nB4 0.5s\nC5 0.5s"
        }
        if p.contains("arpeggio") {
            return "\(extractNote(from: p) ?? "C4") 0.4s\nE4 0.4s\nG4 0.4s\nC5 0.4s\nG4 0.4s\nE4 0.4s\nC4 0.4s"
        }
        return prompt
    }

    private func extractNote(from prompt: String) -> String? {
        let notes = ["C", "D", "E", "F", "G", "A", "B"]
        for note in notes {
            if prompt.range(of: note, options: .caseInsensitive) != nil {
                let octave = prompt.contains("3") ? "3" : (prompt.contains("5") ? "5" : "4")
                return "\(note)\(octave)"
            }
        }
        return nil
    }

    // MARK: - Brain Tools

    private func brainInsights() -> String {
        let insights = app.brain.getInsights()
        return insights.joined(separator: "\n")
    }

    private func brainReport() -> String {
        return app.brain.getBrainReport()
    }

    // MARK: - Ultra-Confirmation Pipeline

    private func ultraConfirmation(_ args: [String: Any]) -> String {
        let sym = resolveSymbol(str(args, "symbol"))
        guard !sym.isEmpty else { return "Missing 'symbol' parameter." }
        let tf = Timeframe(rawValue: str(args, "timeframe")) ?? .m5
        let accountSize = args["account_size"] as? Double ?? Double(str(args, "account_size"))
        let riskPct = args["risk_percent"] as? Double ?? Double(str(args, "risk_percent"))

        // Get current market data
        let candles = app.deriv.priceCache[sym]?.candles ?? []
        let prices = app.deriv.priceCache[sym]?.prices ?? []
        let md = MarketData(symbol: sym, assetClass: DerivSymbols.assetClass(sym), timeframe: tf,
                            candles: candles, currentPrice: prices.last ?? 0)

        guard candles.count > 30 else { return "Insufficient data for \(sym). Need at least 30 candles." }

        // Run the deep analysis
        let ind = TechnicalAnalyzer().analyze(md)
        let agents = ExtendedAgentFactory.fullCouncil().filter { $0.isActive }
        let votes = agents.map { $0.analyze(md, ind) }
        let report = AnalysisReport.build(
            marketData: md, indicators: ind, votes: votes,
            higherTFData: nil, higherTFIndicators: nil,
            requestedTF: tf
        )

        // Run ultra-confirmation pipeline
        let input = UltraConfirmationPipeline.PipelineInput(
            symbol: sym, timeframe: tf,
            accountSize: accountSize, riskPercent: riskPct,
            sessionPreference: nil, currentPosition: nil
        )
        let pipeline = UltraConfirmationPipeline()
        let output = pipeline.run(input: input, report: report)

        return output.formattedReport(symbol: DerivSymbols.display(sym))
    }

    // MARK: - Quantitative Backend Tools

    private func marketData(for symbol: String, timeframe: Timeframe) -> MarketData? {
        let candles = app.deriv.priceCache[symbol]?.candles ?? []
        let price = app.deriv.priceCache[symbol]?.prices.last ?? app.deriv.prices[symbol] ?? candles.last?.close ?? 0
        guard candles.count >= 30, price > 0 else { return nil }
        return MarketData(symbol: symbol, assetClass: DerivSymbols.assetClass(symbol), timeframe: timeframe, candles: candles, currentPrice: price)
    }

    private func quantitativeAnalysis(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty else { return "Missing 'symbol' parameter." }
        guard let md = marketData(for: symbol, timeframe: timeframe) else { return "Insufficient cached candles for \(DerivSymbols.display(symbol)). Open it on Chart first and wait for 30 candles." }
        let accountSize = (args["account_size"] as? Double) ?? Double(str(args, "account_size")) ?? 0
        return BackendQuantEngine.report(for: md, accountSize: accountSize)
    }

    private func backtest(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else { return "Need a symbol with at least 30 cached candles." }
        let fast = Int((args["fast"] as? Double) ?? Double(str(args, "fast")) ?? 10)
        let slow = Int((args["slow"] as? Double) ?? Double(str(args, "slow")) ?? 30)
        guard fast >= 2, slow > fast else { return "Use periods where slow > fast >= 2." }
        let result = BackendQuantEngine.backtest(md.closes, fast: fast, slow: slow)
        return "Backtest (\(DerivSymbols.display(symbol)) \(timeframe.rawValue), SMA \(fast)/\(slow), estimated costs included): \(result.trades) trades · \(Int(result.winRate * 100))% win rate · \(String(format: "%.2f", result.netReturn * 100))% net · \(String(format: "%.2f", result.maxDrawdown * 100))% max drawdown · PF \(result.profitFactor.isFinite ? String(format: "%.2f", result.profitFactor) : "∞"). Historical replay is not a forecast."
    }

    private func riskPlan(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else { return "Need a symbol with at least 30 cached candles." }
        let accountSize = (args["account_size"] as? Double) ?? Double(str(args, "account_size")) ?? 0
        let winRate = (args["win_rate"] as? Double) ?? Double(str(args, "win_rate")) ?? 0.5
        let payoff = (args["payoff_ratio"] as? Double) ?? Double(str(args, "payoff_ratio")) ?? 1.5
        let plan = BackendQuantEngine.riskPlan(md, winRate: min(max(winRate, 0.01), 0.99), payoffRatio: max(payoff, 0.1), accountSize: max(accountSize, 0))
        return "Risk plan for \(DerivSymbols.display(symbol)): stop distance \(String(format: "%.5f", plan.stopDistance)), target \(String(format: "%.5f", plan.targetDistance)), R:R \(String(format: "%.2f", plan.riskReward)), Kelly \(String(format: "%.1f", plan.kellyFraction * 100))%, capped risk \(String(format: "%.1f", plan.cappedRiskFraction * 100))%, 95% VaR \(String(format: "%.2f", plan.valueAtRisk)), CVaR \(String(format: "%.2f", plan.conditionalValueAtRisk))."
    }

    // MARK: - Song Helpers

    private func chordPattern(root: String, minor: Bool) -> String {
        let third = minor ? "Eb" : "E"
        let fifth = "G"
        return """
        chord \(root) \(third)4 \(fifth)4 1s amp 0.6
        rest 0.5s
        chord \(third) \(fifth)4 \(root) 1s amp 0.5
        rest 0.5s
        chord \(fifth)4 \(root) \(third) 1s amp 0.5
        rest 0.5s
        chord \(root) \(third)4 \(fifth)4 2s amp 0.7
        """
    }
}
