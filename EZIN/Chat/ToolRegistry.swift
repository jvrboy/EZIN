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
        case "create_tone":        return createTone(args)
        case "market_overview":    return marketOverview()
        case "brain_insights":     return brainInsights()
        case "brain_report":       return brainReport()
        case "ultra_confirm":      return await ultraConfirmation(args)
        case "quant_analysis":     return quantitativeAnalysis(args)
        case "market_regime":      return marketRegime(args)
        case "performance_snapshot": return performanceSnapshot(args)
        case "export_signal_data": return exportSignalData(args)
        case "backtest":           return backtest(args)
        case "risk_plan":          return riskPlan(args)
        case "structure_confluence": return structureConfluence(args)

        // Real file/document tools — no MCP required to create, read, summarize, rename or delete files.
        case "create_file":        return createFile(args)
        case "read_file":          return readFile(args)
        case "summarize_file":     return summarizeFile(args)
        case "list_files":         return listFiles(args)
        case "rename_file":        return renameFile(args)
        case "delete_file":        return deleteFile(args)

        // App control / memory / web.
        case "app_state":          return appState()
        case "set_setting":        return setSetting(args)
        case "memory_add":         return memoryAdd(args)
        case "memory_search":      return memorySearch(args)
        case "skills_list":        return skillsList()
        case "skill_create":       return skillCreate(args)
        case "skill_import":       return skillImport(args)
        case "web_scrape":         return await webScrape(args)
        case "sentiment_score":    return sentimentScore(args)

        // Advanced hidden backend engines.
        case "full_backend_report": return fullBackendReport(args)
        case "math_analysis":       return mathAnalysis(args)
        case "forex_math":          return forexMath(args)
        case "synthetics_analysis": return syntheticsAnalysis(args)
        case "rng_analysis":        return rngAnalysis(args)
        case "neural_inference":    return neuralInference(args)
        case "chaos_analysis":      return chaosAnalysis(args)
        case "quantum_inspired":    return quantumInspired(args)
        case "bayesian_update":     return bayesianUpdate(args)
        case "fuzzy_signal":        return fuzzySignal(args)
        case "order_flow":          return orderFlow(args)
        case "harmonic_patterns":   return harmonicPatterns(args)
        case "elliott_wave":        return elliottWave(args)
        case "astro_cycles":        return astroCycles(args)
        case "deep_risk":           return deepRisk(args)
        case "walkforward":         return walkforward(args)
        case "correlation_matrix":  return correlationMatrix(args)
        case "session_liquidity":   return sessionLiquidity(args)
        case "anomaly_scan":        return anomalyScan(args)
        case "games_list":          return gamesList()
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
        // Ensure the socket is subscribed to this instrument so live ticks/prices flow
        // even when the user hasn't opened it on the Chart tab yet.
        app.deriv.subscribeTicks(sym)
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

    /// Generate a pure sine-wave tone WAV artifact (frequency + duration + volume).
    /// This is the direct, reliable path for "create a WAV tone" requests — no MCP server needed.
    private func createTone(_ args: [String: Any]) -> String {
        let freq = (args["frequency"] as? Double) ?? Double(str(args, "frequency")) ?? 440
        let dur = (args["duration"] as? Double) ?? Double(str(args, "duration")) ?? 1.0
        let vol = (args["volume"] as? Double) ?? Double(str(args, "volume")) ?? 0.5
        let name = (args["name"] as? String) ?? "tone"
        let clampedVol = max(0.0, min(1.0, vol))
        let clampedDur = max(0.05, min(60.0, dur))
        let clampedFreq = max(1.0, min(20000.0, freq))
        let note = AudioGenerationService.Note(frequency: clampedFreq, duration: clampedDur, amplitude: clampedVol)
        guard let data = AudioGenerationService.generateWAV(notes: [note]) else {
            return "Failed to generate tone."
        }
        guard let art = saveAudioArtifact(data: data, name: name, ext: "wav") else {
            return "Failed to save tone."
        }
        return "Created \(art.name) (\(art.sizeDisplay)) — \(Int(clampedFreq)) Hz sine tone for \(String(format: "%.2f", clampedDur))s at \(Int(clampedVol * 100))% volume."
    }

    /// Live market overview across the main instruments (reads cached tick prices).
    private func marketOverview() -> String {
        let symbols = DerivSymbols.volatility
        var rows: [String] = ["| Instrument | Live Price |", "|---|---|"]
        for sym in symbols {
            if let p = app.deriv.prices[sym] ?? app.deriv.priceCache[sym]?.prices.last, p > 0 {
                let fmt = p > 100 ? String(format: "%.2f", p) : String(format: "%.4f", p)
                rows.append("| \(DerivSymbols.display(sym)) | \(fmt) |")
            }
        }
        guard rows.count > 2 else {
            return "No live prices are cached yet. Open the Chart tab (or run `price(symbol)`) to subscribe to an instrument first."
        }
        return "## Market Overview\n\n" + rows.joined(separator: "\n")
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

    private func ultraConfirmation(_ args: [String: Any]) async -> String {
        let sym = resolveSymbol(str(args, "symbol"))
        guard !sym.isEmpty else { return "Missing 'symbol' parameter." }
        let tf = Timeframe(rawValue: str(args, "timeframe")) ?? .m5
        let accountSize = args["account_size"] as? Double ?? Double(str(args, "account_size"))
        let riskPct = args["risk_percent"] as? Double ?? Double(str(args, "risk_percent"))

        // Ensure the socket is subscribed so live data flows for symbols not yet opened on Chart.
        app.deriv.subscribeTicks(sym)
        // Build the deep multi-timeframe report (async pipeline).
        let mtf = MultiTimeframeEngine(deriv: app.deriv, engine: app.engine)
        guard let report = await mtf.analyze(symbol: sym, requested: tf) else {
            return "No market data available for \(DerivSymbols.display(sym)). Open it on the Chart tab to subscribe, or check the connection."
        }

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

    private func marketRegime(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty else { return "Missing 'symbol' parameter." }
        guard let md = marketData(for: symbol, timeframe: timeframe) else { return "Need a symbol with at least 30 cached candles." }
        return BackendQuantEngine.regimeReport(for: md, symbol: DerivSymbols.display(symbol))
    }

    private func performanceSnapshot(_ args: [String: Any]) -> String {
        let symbolRaw = resolveSymbol(str(args, "symbol"))
        let symbol = symbolRaw.isEmpty ? nil : symbolRaw
        let tfRaw = str(args, "timeframe")
        let timeframe = tfRaw.isEmpty ? nil : Timeframe(rawValue: tfRaw)
        return app.signalPerformance.formattedSnapshot(symbol: symbol, timeframe: timeframe)
    }

    private func exportSignalData(_ args: [String: Any]) -> String {
        let format = str(args, "format").lowercased()
        guard format.isEmpty || format == "csv" else { return "Supported export formats: csv." }
        let symbolRaw = resolveSymbol(str(args, "symbol"))
        let symbol = symbolRaw.isEmpty ? nil : symbolRaw
        let tfRaw = str(args, "timeframe")
        let timeframe = tfRaw.isEmpty ? nil : Timeframe(rawValue: tfRaw)
        let csv = app.signalPerformance.exportTrackedSignalsCSV(symbol: symbol, timeframe: timeframe)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "signal-performance-\(stamp).csv"
        let data = Data(csv.utf8)
        let url = FileStore.shared.saveData(data, name: fileName, in: FileStore.shared.artifactsDir)
        let relPath = FileStore.shared.relativePath(url)
        let artifact = Artifact(name: fileName, relativePath: relPath, kind: "csv", byteSize: Int64(data.count))
        ArtifactStore.shared.add(artifact)
        return "Exported \(fileName) (\(artifact.sizeDisplay))."
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

    private func structureConfluence(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else { return "Need a symbol with at least 30 cached candles." }
        return ConfluenceAnalysisEngine.formatted(ConfluenceAnalysisEngine.analyze(md), symbol: DerivSymbols.display(symbol))
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


    // MARK: - File / document tools (no MCP required)

    private func sanitizedFileName(_ raw: String, fallbackExt: String = "txt") -> String {
        let cleaned = raw.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let name = cleaned.isEmpty ? "file-\(Int(Date().timeIntervalSince1970))" : cleaned
        return name.contains(".") ? name : "\(name).\(fallbackExt)"
    }

    private func createFile(_ args: [String: Any]) -> String {
        let name = sanitizedFileName(str(args, "name").isEmpty ? str(args, "filename") : str(args, "name"), fallbackExt: str(args, "kind").isEmpty ? "txt" : str(args, "kind"))
        let content = str(args, "content")
        let folder = str(args, "folder").lowercased()
        let dir = folder.contains("project") ? FileStore.shared.projectsDir : FileStore.shared.artifactsDir
        let data = Data(content.utf8)
        let url = FileStore.shared.saveData(data, name: name, in: dir)
        let rel = FileStore.shared.relativePath(url)
        let artifact = Artifact(name: name, relativePath: rel, kind: (name as NSString).pathExtension.lowercased(), byteSize: Int64(data.count))
        ArtifactStore.shared.add(artifact)
        return "Created \(name) (\(artifact.sizeDisplay)) at \(rel). No MCP server was needed — the app has real file tools."
    }

    private func readFile(_ args: [String: Any]) -> String {
        let query = str(args, "name").isEmpty ? str(args, "path") : str(args, "name")
        let chars = Int((args["chars"] as? Double) ?? Double(str(args, "chars")) ?? 2000)
        return DocumentIntelligence.filePreview(query, chars: max(200, min(chars, 12000)))
    }

    private func summarizeFile(_ args: [String: Any]) -> String {
        let query = str(args, "name").isEmpty ? str(args, "path") : str(args, "name")
        let sentences = Int((args["sentences"] as? Double) ?? Double(str(args, "sentences")) ?? 10)
        return DocumentIntelligence.summarizeFile(query, maxSentences: max(3, min(sentences, 20)))
    }

    private func listFiles(_ args: [String: Any]) -> String {
        let scope = str(args, "scope").lowercased()
        let root = scope.contains("project") ? FileStore.shared.projectsDir : scope.contains("chat") ? FileStore.shared.chatDir : FileStore.shared.artifactsDir
        let fm = FileStore.shared.fm
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return "No files found."
        }
        func modDate(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        let rows = items.sorted { modDate($0) > modDate($1) }.prefix(40).map { url -> String in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return "• \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
        }
        return rows.isEmpty ? "No files found." : "## Files\n" + rows.joined(separator: "\n")
    }

    private func renameFile(_ args: [String: Any]) -> String {
        let from = str(args, "from").isEmpty ? str(args, "name") : str(args, "from")
        let to = sanitizedFileName(str(args, "to"))
        guard let src = DocumentIntelligence.resolveFile(from) else { return "No file found for '\(from)'." }
        let dst = src.deletingLastPathComponent().appendingPathComponent(to)
        do {
            try FileStore.shared.fm.moveItem(at: src, to: dst)
            let rel = FileStore.shared.relativePath(dst)
            let artifact = Artifact(name: to, relativePath: rel, kind: dst.pathExtension.lowercased(), byteSize: FileStore.shared.fileSize(atRelative: rel))
            ArtifactStore.shared.add(artifact)
            return "Renamed \(src.lastPathComponent) → \(to)."
        } catch {
            return "Rename failed: \(error.localizedDescription)"
        }
    }

    private func deleteFile(_ args: [String: Any]) -> String {
        let query = str(args, "name").isEmpty ? str(args, "path") : str(args, "name")
        guard let src = DocumentIntelligence.resolveFile(query) else { return "No file found for '\(query)'." }
        let bin = FileStore.shared.chatDir.appendingPathComponent("Bin", isDirectory: true)
        let dst = bin.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(src.lastPathComponent)")
        do {
            try FileStore.shared.fm.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileStore.shared.fm.moveItem(at: src, to: dst)
            return "Moved \(src.lastPathComponent) to the file bin: \(FileStore.shared.relativePath(dst)). It can be recovered from Chat/Bin."
        } catch {
            return "Delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - App state / settings / memory / web

    private func appState() -> String {
        let cfg = ChatConfigStore.shared.config
        return """
        ## App State
        - Connection: \(app.connectionState.label) · authorized: \(app.deriv.authorized ? "yes" : "no") · last auto-refresh: \(app.lastAutoRefreshAt?.formatted(date: .omitted, time: .standard) ?? "pending")
        - Bot: \(app.bot.running ? "running" : "not running") · live signals: \(app.signals.count) · closed trades cached: \(app.history.count)
        - Watchlist: \(app.settings.watchlist.map { DerivSymbols.display($0) }.joined(separator: ", "))
        - Chat: autoRoute \(cfg.autoRoute ? "on" : "off") · trading \(cfg.allowTrading ? "enabled" : "disabled") · temperature \(String(format: "%.2f", cfg.temperature))
        - Note: iOS permits best-effort background refresh, not guaranteed 24/7 execution while suspended; foreground heartbeat is every 5s and system background tasks are registered.
        """
    }

    private func setSetting(_ args: [String: Any]) -> String {
        let key = str(args, "key").lowercased()
        let value = str(args, "value")
        func boolValue() -> Bool { ["1", "true", "yes", "on", "enabled"].contains(value.lowercased()) }
        switch key {
        case "push_alerts", "pushalerts":
            app.settings.pushAlerts = boolValue()
            return "Push alerts set to \(app.settings.pushAlerts)."
        case "allow_trading", "allowtrading":
            ChatConfigStore.shared.config.allowTrading = boolValue()
            return "Chat trading set to \(ChatConfigStore.shared.config.allowTrading)."
        case "auto_route", "autoroute":
            ChatConfigStore.shared.config.autoRoute = boolValue()
            return "Auto-route set to \(ChatConfigStore.shared.config.autoRoute)."
        case "temperature":
            let t = max(0, min(1.5, Double(value) ?? 0.4))
            ChatConfigStore.shared.config.temperature = t
            return "Temperature set to \(String(format: "%.2f", t))."
        case "watchlist":
            let symbols = value.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }.filter { DerivSymbols.all.contains($0) }
            guard !symbols.isEmpty else { return "No valid symbols in value. Use comma-separated Deriv symbols." }
            app.settings.watchlist = Array(Set(symbols)).sorted()
            return "Watchlist updated: \(app.settings.watchlist.map { DerivSymbols.display($0) }.joined(separator: ", "))."
        default:
            return "Supported settings: push_alerts, allow_trading, auto_route, temperature, watchlist."
        }
    }

    private var memoryFileURL: URL { FileStore.shared.chatDir.appendingPathComponent("memory.jsonl") }

    private func memoryAdd(_ args: [String: Any]) -> String {
        let text = str(args, "text").isEmpty ? str(args, "memory") : str(args, "text")
        guard !text.isEmpty else { return "Missing memory text." }
        let record: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return "Failed to encode memory." }
        if let handle = try? FileHandle(forWritingTo: memoryFileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
        } else {
            try? (data + Data("\n".utf8)).write(to: memoryFileURL)
        }
        return "Memory saved. I can search it with memory_search(query)."
    }

    private func memorySearch(_ args: [String: Any]) -> String {
        let query = str(args, "query").lowercased()
        guard let raw = try? String(contentsOf: memoryFileURL, encoding: .utf8), !raw.isEmpty else { return "No saved memories yet." }
        let lines = raw.split(separator: "\n").map(String.init)
        let matches = lines.filter { query.isEmpty || $0.lowercased().contains(query) }.suffix(8)
        return matches.isEmpty ? "No memories matched '\(query)'." : "## Memory\n" + matches.joined(separator: "\n")
    }

    private func skillsList() -> String {
        "## Installed Skills\n" + SkillStore.shared.promptSummary(limit: 30)
    }

    private func skillCreate(_ args: [String: Any]) -> String {
        let name = str(args, "name")
        let content = str(args, "content")
        guard !name.isEmpty, !content.isEmpty else { return "skill_create requires name and content." }
        let skill = SkillStore.shared.create(
            name: name,
            format: str(args, "format").isEmpty ? "md" : str(args, "format"),
            summary: str(args, "summary").isEmpty ? "Custom chat skill" : str(args, "summary"),
            content: content,
            tools: (args["tools"] as? [String]) ?? str(args, "tools").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            executionScripts: (args["execution_scripts"] as? [String]) ?? []
        )
        return "Installed skill '\(skill.name)' [\(skill.format)]. It is now available to the assistant via skills_list."
    }

    private func skillImport(_ args: [String: Any]) -> String {
        let text = str(args, "text").isEmpty ? str(args, "content") : str(args, "text")
        guard !text.isEmpty else { return "skill_import requires text/content (MD, SKILL, JSON, and more text formats are supported)." }
        let skill = SkillStore.shared.importText(text, suggestedName: str(args, "name").isEmpty ? "Imported Skill" : str(args, "name"))
        return "Imported skill '\(skill.name)' [\(skill.format)]."
    }

    private func webScrape(_ args: [String: Any]) async -> String {
        let raw = str(args, "url")
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return "Provide a valid http(s) URL."
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let html = String(data: data.prefix(250_000), encoding: .utf8) ?? ""
            let title = (html.range(of: "<title>(.*?)</title>", options: [.regularExpression, .caseInsensitive]).map { String(html[$0]) } ?? "untitled")
                .replacingOccurrences(of: "</?title>", with: "", options: .regularExpression)
            let text = html
                .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = DocumentIntelligence.summarize(text, maxSentences: 6, maxChars: 1800)
            return "## Web Scrape\n**\(title)**\n\(url.absoluteString)\n\n" + (summary.isEmpty ? String(text.prefix(1200)) : summary)
        } catch {
            return "Web scrape failed: \(error.localizedDescription)"
        }
    }

    private func sentimentScore(_ args: [String: Any]) -> String {
        let text = str(args, "text").isEmpty ? str(args, "headline") : str(args, "text")
        guard !text.isEmpty else { return "Missing text/headline." }
        let positive: Set<String> = ["beat", "beats", "surge", "surges", "rally", "rallies", "growth", "strong", "upgrade", "upgraded", "record", "profit", "dovish", "stimulus", "approval", "bullish", "expands", "wins", "breakthrough"]
        let negative: Set<String> = ["miss", "misses", "crash", "crashes", "selloff", "sell-off", "weak", "downgrade", "downgraded", "loss", "hawkish", "ban", "banned", "lawsuit", "fraud", "bearish", "contracts", "fear", "default", "war"]
        let toks = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let pos = toks.filter { positive.contains($0) }.count
        let neg = toks.filter { negative.contains($0) }.count
        let score = max(-1.0, min(1.0, Double(pos - neg) / Double(max(2, pos + neg + 1))))
        let label = score > 0.25 ? "bullish/positive" : score < -0.25 ? "bearish/negative" : "neutral/mixed"
        return "Sentiment score: \(String(format: "%.2f", score)) (\(label)) · positive hits \(pos) · negative hits \(neg). Use inject_news to push this into the news-reactive agent."
    }

    // MARK: - Advanced backend tools

    private func mdFor(_ args: [String: Any]) -> (MarketData?, String) {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty else { return (nil, "Missing 'symbol' parameter.") }
        app.deriv.subscribeTicks(symbol)
        guard let md = marketData(for: symbol, timeframe: timeframe) else {
            return (nil, "Need at least 30 cached candles for \(DerivSymbols.display(symbol)). Run analyze(symbol,timeframe) first or open the chart for a few seconds.")
        }
        return (md, "")
    }

    private func fullBackendReport(_ args: [String: Any]) -> String {
        let (md, err) = mdFor(args); guard let md else { return err }
        let account = (args["account_size"] as? Double) ?? Double(str(args, "account_size")) ?? 0
        return AdvancedBackend.fullBackendReport(for: md, accountSize: account)
    }

    private func mathAnalysis(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.mathematicalReport(for: md) }
    private func forexMath(_ args: [String: Any]) -> String {
        let (md, err) = mdFor(args); guard let md else { return err }
        let domestic = (args["domestic_rate"] as? Double) ?? Double(str(args, "domestic_rate")) ?? 0.05
        let foreign = (args["foreign_rate"] as? Double) ?? Double(str(args, "foreign_rate")) ?? 0.03
        let days = (args["days"] as? Double) ?? Double(str(args, "days")) ?? 30
        return AdvancedBackend.forexMathReport(for: md, domesticRate: domestic, foreignRate: foreign, days: days)
    }
    private func syntheticsAnalysis(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.syntheticsReport(for: md) }
    private func rngAnalysis(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.rngReport(for: md) }
    private func neuralInference(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.neuralReport(for: md) }
    private func chaosAnalysis(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.chaosReport(for: md) }
    private func quantumInspired(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.quantumInspiredReport(for: md) }
    private func bayesianUpdate(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.bayesianReport(for: md) }
    private func fuzzySignal(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.fuzzyReport(for: md) }
    private func orderFlow(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.orderFlowReport(for: md) }
    private func harmonicPatterns(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.harmonicReport(for: md) }
    private func elliottWave(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.elliottReport(for: md) }
    private func astroCycles(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.astroReport(for: md) }
    private func deepRisk(_ args: [String: Any]) -> String {
        let (md, err) = mdFor(args); guard let md else { return err }
        let account = (args["account_size"] as? Double) ?? Double(str(args, "account_size")) ?? 0
        return AdvancedBackend.deepRiskReport(for: md, accountSize: account)
    }
    private func walkforward(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.walkforwardReport(for: md) }
    private func sessionLiquidity(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.sessionLiquidityReport(for: md) }
    private func anomalyScan(_ args: [String: Any]) -> String { let (md, err) = mdFor(args); guard let md else { return err }; return AdvancedBackend.anomalyReport(for: md) }

    private func correlationMatrix(_ args: [String: Any]) -> String {
        let raw = str(args, "symbols")
        let symbols = raw.isEmpty ? app.settings.watchlist : raw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }
        var series: [String: [Double]] = [:]
        for symbol in Set(symbols).sorted() {
            if let closes = app.deriv.priceCache[symbol]?.prices, closes.count >= 30 { series[symbol] = closes }
        }
        guard series.count >= 2 else { return "Need cached candles for at least two watchlist symbols. Run analyze on two instruments or open charts first." }
        return AdvancedBackend.correlationMatrix(series: series)
    }

    private func gamesList() -> String {
        """
        ## EZIN Arcade
        - Quantum Cat Box — quantum prediction and collapse
        - Frequency Frog — scales, chords and intervals
        - Fraction Fighter — math combat
        - Gravity Golf — projectile physics across planets
        - Tower of Babel — translations and false friends
        - Taxonomy Tetris — classify organisms before the stack rises
        Open the GAMES tab to play them inside the app.
        """
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
