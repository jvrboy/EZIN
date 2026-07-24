import Foundation

/// Executes the in-app + MCP tools the chat agent can call.
@MainActor
struct ToolRegistry {
    let app: AppState

    func run(_ name: String, args: [String: Any]) async -> String {
        if let virtualTool = BackendToolExpansion.virtualTool(named: name) {
            return BackendToolExpansion.run(virtualTool, args: args, registry: self)
        }

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
        case "backend_tool_catalog": return BackendToolExpansion.catalogMarkdown()
        case "agentic_pipeline_catalog": return BackendToolExpansion.pipelineMarkdown()
        case "agentic_power_plan":   return BackendToolExpansion.powerPlan(args: args, registry: self)
        case "connector_catalog":    return connectorCatalog()
        case "swarm_status":         return swarmStatus()
        case "production_health":    return productionHealth()

        // APEX second-generation analysis layer.
        case "master_confluence":   return masterConfluenceTool(args)
        case "pattern_scan":        return patternScanTool(args)
        case "market_profile":      return marketProfileTool(args)
        case "liquidity_map":       return liquidityMapTool(args)
        case "range_forecast":      return rangeForecastTool(args)
        case "entropy_analysis":    return entropyAnalysisTool(args)
        case "symbol_scanner":      return symbolScannerTool(args)

        // VINNY — the Unified Sound Intelligence Engine.
        case "vinny_loop":          return await vinnyLoopTool(args)
        case "vinny_patch":         return await vinnyPatchTool(args)
        case "vinny_reference":     return await vinnyReferenceTool(args)
        case "vinny_stems":         return await vinnyStemsTool(args)
        case "vinny_library":       return vinnyLibraryTool(args)

        // Portfolio Engine — multi-asset optimization, risk parity, efficient frontier, Kelly allocation.
        case "portfolio_analysis":   return portfolioAnalysis(args)
        case "portfolio_rebalance":  return portfolioRebalance(args)
        case "portfolio_stress":     return portfolioStress(args)

        // Alert System — price, indicator, and volatility alerts.
        case "alert_create":         return alertCreate(args: args)
        case "alert_list":           return alertList(args: args)
        case "alert_delete":         return alertDelete(args: args)
        case "alert_acknowledge":    return alertAcknowledge(args: args)

        // Backtesting Framework — full strategy backtesting, comparison, walk-forward, and optimization.
        case "backtest_strategy":    return backtestStrategy(args)
        case "backtest_compare":     return backtestCompare(args)
        case "backtest_walkforward": return backtestWalkforward(args)
        case "backtest_optimize":    return backtestOptimize(args)

        // Pattern Recognition — advanced chart patterns, support/resistance, volume patterns.
        case "pattern_scan_advanced": return patternScanAdvanced(args)

        // Signal Fusion — unified engine that merges ALL analysis engines into one verdict.
        case "signal_fusion":        return signalFusion(args)
        case "fusion_weights":       return fusionWeights(args)

        // Trade Journal — log, search, close, and analyze your personal trades.
        case "journal_add":           return journalAdd(args: args)
        case "journal_list":          return journalList(args: args)
        case "journal_close":         return journalClose(args: args)
        case "journal_search":        return journalSearch(args: args)
        case "journal_stats":         return journalStats(args: args)
        case "journal_lesson":        return journalLesson(args: args)

        // Economic Calendar — upcoming high-impact events and market-moving data.
        case "calendar_events":       return calendarEvents(args: args)
        case "calendar_high_impact":  return calendarHighImpact(args: args)
        case "calendar_next":         return calendarNext(args: args)

        // Position & Risk Calculator — size your trades, calculate pips, manage risk.
        case "calculate_position":    return calculatePosition(args: args)
        case "calculate_risk":        return calculateRisk(args: args)
        case "calculate_pips":        return calculatePips(args: args)
        case "calculate_pnl":         return calculatePnL(args: args)

        // Market News Feed — browse, search, bookmark, and analyze market news.
        case "news_list":              return newsList(args: args)
        case "news_search":            return newsSearch(args: args)
        case "news_sentiment":         return newsSentiment(args: args)
        case "news_by_symbol":         return newsBySymbol(args: args)
        case "news_add":               return newsAdd(args: args)
        case "news_latest":            return newsLatest(args: args)
        case "dashboard_summary":      return dashboardSummary()

        // AI Chat Pipeline — structured reasoning, thinking, and processing.
        case "run_pipeline":              return await runPipeline(args: args)
        case "pipeline_status":           return pipelineStatus()
        case "pipeline_summary":          return pipelineSummary()

        // Chat Tool Expansion — calculator, stats, regression, education, utilities.
        case "calculate":                 return calculateTool(args: args)
        case "validate_json":             return validateJSONTool(args: args)
        case "convert_base":              return convertBaseTool(args: args)
        case "random_numbers":            return randomNumbersTool(args: args)
        case "statistics":                return statisticsTool(args: args)
        case "linear_regression":         return linearRegressionTool(args: args)
        case "correlation":               return correlationTool(args: args)
        case "explain":                   return explainConceptTool(args: args)
        case "trading_plan":              return tradingPlanTool(args: args)
        case "currency_convert":          return currencyConvertTool(args: args)
        case "countdown":                 return countdownTool(args: args)
        case "checklist":                 return checklistTool(args: args)
        case "market_health":             return marketHealthTool()

        // Bot Strategy Library — explore and configure strategies.
        case "bot_strategies":            return botStrategiesTool(args: args)
        case "strategy_detail":           return strategyDetailTool(args: args)

        // Skills Extension — enhanced skills management.
        case "skills_catalog":            return skillsCatalogTool()
        case "skill_export":              return skillExportTool(args: args)
        case "skill_import":              return skillImportTool(args: args)
        case "skill_create_custom":       return skillCreateCustomTool(args: args)
        default:               return "Unknown tool: \(name)"
        }
    }

    // MARK: helpers
    // (internal so tool extensions in ApexChatTools/VinnyChatTools can reuse them)
    func str(_ a: [String: Any], _ k: String) -> String { (a[k] as? String) ?? "" }

    func resolveSymbol(_ s: String) -> String {
        if DerivSymbols.all.contains(s) { return s }
        if let m = DerivSymbols.all.first(where: { DerivSymbols.display($0).lowercased() == s.lowercased() }) { return m }
        if let m = DerivSymbols.all.first(where: { DerivSymbols.display($0).lowercased().contains(s.lowercased()) && !s.isEmpty }) { return m }
        return s
    }

    func resolveTF(_ s: String) -> Timeframe { Timeframe(rawValue: s) ?? .m5 }

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


    private func connectorCatalog() -> String {
        let rows = MCPStore.shared.connectors.map { connector in
            let state = connector.enabled ? "enabled" : "disabled"
            let url = connector.url.isEmpty ? "not configured" : connector.url
            return "• \(connector.name) [\(connector.kind.title)] — \(state), \(url)"
        }
        return "## MCP Connector Catalog\n\n" + (rows.isEmpty ? "No MCP connectors configured." : rows.joined(separator: "\n"))
    }

    private func swarmStatus() -> String {
        let activeAgents = app.engine.agents.filter { $0.isActive }.count
        return "## Swarm Status\n\nChat swarm: \(AgentRegistry.agents.count) specialists · \(AgentRegistry.pipelines.count) pipelines.\nSignal council: \(activeAgents)/\(app.engine.agents.count) active agents.\nRuntime loops: bot scanning=\(botScanningDescription), websocket=\(connectionDescription)."
    }

    private var botScanningDescription: String { app.bot.running ? "on" : "off" }

    private var connectionDescription: String {
        switch app.connectionState {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .disconnected: return "disconnected"
        case .error(let message): return "error(\(message))"
        }
    }

    private func productionHealth() -> String {
        let enabledConnectors = MCPStore.shared.connectors.filter { $0.enabled }.count
        let subscribed = app.deriv.subscribedSymbolsSnapshot.count
        let prices = app.deriv.prices.count
        let warnings = [
            app.booted ? nil : "boot has not completed",
            app.connectionState == .connected ? nil : "Deriv socket is not connected",
            enabledConnectors > 0 ? nil : "no MCP connectors enabled",
            prices > 0 ? nil : "no live prices cached yet"
        ].compactMap { $0 }
        let warningText = warnings.isEmpty ? "No immediate production warnings detected." : warnings.map { "• \($0)" }.joined(separator: "\n")
        return "## Production Health\n\nBooted: \(app.booted)\nConnection: \(connectionDescription)\nSubscribed symbols: \(subscribed)\nCached live prices: \(prices)\nEnabled MCP connectors: \(enabledConnectors)\nActive chat agents: \(AgentRegistry.agents.count)\nPipelines: \(AgentRegistry.pipelines.count)\n\nWarnings:\n\(warningText)"
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

    func marketData(for symbol: String, timeframe: Timeframe) -> MarketData? {
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

    // MARK: - Portfolio Engine Tools

    /// Portfolio analysis — multi-asset optimization, risk parity, efficient frontier.
    private func portfolioAnalysis(_ args: [String: Any]) -> String {
        let symbolsRaw = str(args, "symbols")
        let symbols: [String]
        if symbolsRaw.isEmpty {
            symbols = Array(app.settings.watchlist.prefix(6))
        } else {
            symbols = symbolsRaw.split(separator: ",").map {
                resolveSymbol(String($0).trimmingCharacters(in: .whitespaces))
            }
        }

        guard !symbols.isEmpty else { return "No symbols specified and watchlist is empty. Use symbols='R_100,1HZ10V,...' or add to watchlist." }

        var assets: [PortfolioEngine.AssetInput] = []
        for symbol in symbols {
            if let prices = app.deriv.priceCache[symbol]?.prices, prices.count >= 30 {
                assets.append(PortfolioEngine.AssetInput(symbol: symbol, prices: prices))
            }
        }

        guard assets.count >= 2 else {
            if assets.count == 1 {
                return PortfolioEngine.portfolioReport(assets: assets)
            }
            return "Need cached price data for at least 2 symbols. Open charts for your watchlist symbols or use analyze() to subscribe."
        }

        return PortfolioEngine.portfolioReport(assets: assets)
    }

    /// Portfolio rebalancing suggestions based on current vs optimal allocation.
    private func portfolioRebalance(_ args: [String: Any]) -> String {
        let symbolsRaw = str(args, "symbols")
        let currentRaw = str(args, "current_weights")
        let symbols = symbolsRaw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }
        let currentStrs = currentRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard symbols.count == currentStrs.count, symbols.count >= 2 else {
            return "Provide matching 'symbols' and 'current_weights' as comma-separated lists. Example: symbols='R_100,1HZ10V' current_weights='0.6,0.4'"
        }

        let currentWeights = currentStrs.compactMap { Double($0) }
        guard currentWeights.count == symbols.count else { return "Could not parse all weights as numbers." }
        let weightSum = currentWeights.reduce(0, +)
        guard abs(weightSum - 1.0) < 0.01 else { return "Weights must sum to approximately 1.0 (currently \(String(format: "%.2f", weightSum)))." }

        // Get cached prices for optimization
        var assets: [PortfolioEngine.AssetInput] = []
        for symbol in symbols {
            if let prices = app.deriv.priceCache[symbol]?.prices, prices.count >= 30 {
                assets.append(PortfolioEngine.AssetInput(symbol: symbol, prices: prices))
            }
        }

        guard assets.count >= 2 else { return "Need cached prices for at least 2 symbols. Open charts first." }

        // Get target allocation from max Sharpe portfolio
        guard let (targetAlloc, metrics) = PortfolioEngine.maxSharpePortfolio(assets: assets) else {
            return "Could not compute optimal portfolio from available data."
        }

        let currentAlloc = zip(symbols, currentWeights).map {
            PortfolioEngine.Allocation(symbol: $0, weight: $1)
        }

        let suggestions = PortfolioEngine.rebalanceSuggestions(
            currentAllocations: currentAlloc,
            targetAllocations: targetAlloc
        )

        var report = "## Portfolio Rebalancing\n\n"
        report += "**Optimal Portfolio** (Sharpe \(String(format: "%.2f", metrics.sharpeRatio)))\n\n"
        report += "| Symbol | Current | Target | Drift | Action | Urgency |\n|---|---|---|---|---|---|\n"
        for s in suggestions {
            report += "| \(DerivSymbols.display(s.symbol)) | \(String(format: "%.1f", s.currentWeight * 100))% | \(String(format: "%.1f", s.targetWeight * 100))% | \(String(format: "%.1f", s.drift * 100))% | \(s.action.uppercased()) | \(s.urgency) |\n"
        }

        report += "\n**Current portfolio metrics:**\n"
        report += "- Expected return: \(String(format: "%.2f", metrics.expectedReturn * 100))%\n"
        report += "- Volatility: \(String(format: "%.2f", metrics.volatility * 100))%\n"
        report += "- Sharpe: \(String(format: "%.2f", metrics.sharpeRatio))\n"
        report += "- Max drawdown: \(String(format: "%.1f", metrics.maxDrawdown * 100))%\n"

        return report
    }

    /// Portfolio stress tests.
    private func portfolioStress(_ args: [String: Any]) -> String {
        let symbolsRaw = str(args, "symbols")
        let symbols = symbolsRaw.isEmpty ? Array(app.settings.watchlist.prefix(6)) : symbolsRaw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }

        var assets: [PortfolioEngine.AssetInput] = []
        for symbol in symbols {
            if let prices = app.deriv.priceCache[symbol]?.prices, prices.count >= 30 {
                assets.append(PortfolioEngine.AssetInput(symbol: symbol, prices: prices))
            }
        }

        guard assets.count >= 2 else { return "Need cached prices for at least 2 symbols." }

        let equalWeight = 1.0 / Double(assets.count)
        let allocations = assets.map { PortfolioEngine.Allocation(symbol: $0.symbol, weight: equalWeight) }
        let stressResults = PortfolioEngine.stressTest(allocations: allocations, assets: assets)

        var report = "## Portfolio Stress Tests\n\n"
        report += "**Equal-weight portfolio across \(assets.count) instruments**\n\n"
        report += "| Scenario | Impact | Max DD | Est. Recovery |\n|---|---|---|---|\n"
        for test in stressResults {
            report += "| \(test.scenario) | \(String(format: "%.1f", test.impact * 100))% | \(String(format: "%.1f", test.maxDrawdown * 100))% | ~\(test.recoveryBars) bars |\n"
        }

        // Add symbols
        report += "\n**Symbols tested:**\n"
        for asset in assets {
            report += "- \(DerivSymbols.display(asset.symbol))\n"
        }

        return report
    }

    // MARK: - Backtesting Framework Tools

    /// Run a full backtest with configurable strategy, parameters, and cost model.
    private func backtestStrategy(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        let strategyName = str(args, "strategy").isEmpty ? "sma" : str(args, "strategy")
        let costModelName = str(args, "cost_model").lowercased()

        guard !symbol.isEmpty else { return "Missing 'symbol' parameter." }
        guard let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Insufficient cached candles for \(DerivSymbols.display(symbol)). Open the Chart tab first to cache data."
        }

        var params: [String: Double] = [:]
        if let fast = (args["fast"] as? Double) ?? Double(str(args, "fast")) { params["fast"] = fast }
        if let slow = (args["slow"] as? Double) ?? Double(str(args, "slow")) { params["slow"] = slow }
        if let period = (args["period"] as? Double) ?? Double(str(args, "period")) { params["period"] = period }
        if let signal = (args["signal"] as? Double) ?? Double(str(args, "signal")) { params["signal"] = signal }
        if let oversold = (args["oversold"] as? Double) ?? Double(str(args, "oversold")) { params["oversold"] = oversold }
        if let overbought = (args["overbought"] as? Double) ?? Double(str(args, "overbought")) { params["overbought"] = overbought }

        let costModel: BacktestingFramework.CostModel
        switch costModelName {
        case "zero": costModel = .zero
        case "forex", "fx": costModel = .forex
        default: costModel = .default
        }

        return BacktestingFramework.backtestReport(
            strategyName: strategyName,
            symbol: symbol,
            candles: md.candles,
            parameters: params,
            costModel: costModel
        )
    }

    /// Compare multiple strategies on the same instrument.
    private func backtestCompare(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))

        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need cached candles for \(DerivSymbols.display(symbol))."
        }

        // Run comparison with built-in strategies
        var sma: BacktestingFramework.SMACrossoverStrategy = .init()
        var rsi: BacktestingFramework.RSIMeanReversionStrategy = .init()
        var macd: BacktestingFramework.MACDStrategy = .init()

        let strategies: [any BacktestStrategy] = [sma, rsi, macd]

        return BacktestingFramework.compareStrategies(
            strategies: strategies,
            symbol: symbol,
            candles: md.candles
        )
    }

    /// Walk-forward analysis on a strategy.
    private func backtestWalkforward(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))

        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need cached candles for \(DerivSymbols.display(symbol))."
        }

        let result = BacktestingFramework.walkForward(
            strategyType: { params in
                BacktestingFramework.SMACrossoverStrategy(
                    fast: Int(params["fast"] != 0 ? params["fast"] : 10),
                    slow: Int(params["slow"] != 0 ? params["slow"] : 30)
                )
            },
            symbol: symbol,
            candles: md.candles,
            windows: 3
        )

        var report = "## Walk-Forward Analysis — \(DerivSymbols.display(symbol))\n\n"
        report += "\(result.summary)\n\n"
        report += "| Window | Trades | Return | Max DD | Sharpe |\n|---|---|---|---|---|\n"
        for (i, w) in result.windows.enumerated() {
            report += "| Window \(i + 1) | \(w.totalTrades) | \(BacktestingFramework.fmt(w.totalReturnPct))% | \(BacktestingFramework.fmt(w.maxDrawdownPct))% | \(BacktestingFramework.fmt(w.sharpeRatio)) |\n"
        }
        report += "\n**Averages:** Return \(BacktestingFramework.fmt(result.averageReturnPct))% · Max DD \(BacktestingFramework.fmt(result.averageMaxDD))% · Sharpe \(BacktestingFramework.fmt(result.averageSharpe))\n"
        report += "**Consistency:** \(BacktestingFramework.fmt(result.consistencyScore * 100))% · Parameter Stability: \(BacktestingFramework.fmt(result.parameterStability * 100))%\n"

        return report
    }

    /// Genetic parameter optimization.
    private func backtestOptimize(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))

        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe), md.candles.count > 60 else {
            return "Need at least 60 cached candles for \(DerivSymbols.display(symbol))."
        }

        let result = BacktestingFramework.optimizeGenetic(
            strategyType: { params in
                BacktestingFramework.SMACrossoverStrategy(
                    fast: Int(params["fast"] != 0 ? params["fast"] : 10),
                    slow: Int(params["slow"] != 0 ? params["slow"] : 30)
                )
            },
            candles: md.candles,
            generations: 20,
            population: 25
        )

        var report = "## Parameter Optimization — \(DerivSymbols.display(symbol))\n\n"
        report += "**Best Score:** \(BacktestingFramework.fmt(result.bestScore))\n\n"
        report += "**Best Parameters:**\n"
        for (key, value) in result.bestParameters.values.sorted(by: { $0.key < $1.key }) {
            report += "- \(key): \(Int(value))\n"
        }
        report += "\n**Top Candidates:**\n"
        for (i, r) in result.topResults.prefix(3).enumerated() {
            report += "\(i + 1). Score \(BacktestingFramework.fmt(r.score)) — "
            report += r.parameters.values.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\(Int($0.value))" }.joined(separator: ", ")
            report += "\n"
        }

        return report
    }

    // MARK: - Pattern Recognition Tools

    /// Advanced pattern scan — detects chart patterns, support/resistance, and volume patterns.
    private func patternScanAdvanced(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))

        guard !symbol.isEmpty else { return "Missing 'symbol' parameter." }
        guard let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Insufficient cached candles for \(DerivSymbols.display(symbol)). Open the Chart tab first."
        }

        return PatternRecognition.patternReport(candles: md.candles, symbol: symbol)
    }

    // MARK: - Signal Fusion Tools

    /// Signal fusion — merges ALL analysis engines into one unified verdict.
    private func signalFusion(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))

        guard !symbol.isEmpty else { return "Missing 'symbol' parameter." }
        app.deriv.subscribeTicks(symbol)

        let inputs = SignalFusionEngine.buildInputs(symbol: symbol, timeframe: timeframe, app: app)
        guard !inputs.isEmpty else {
            return "No engine inputs available for \(DerivSymbols.display(symbol)). Open the Chart tab first or try a different symbol."
        }

        return SignalFusionEngine.fusionReport(symbol: symbol, inputs: inputs)
    }

    /// View and optionally reset dynamic fusion weights.
    private func fusionWeights(_ args: [String: Any]) -> String {
        let reset = str(args, "reset").lowercased() == "true"
        let tracker = SignalFusionEngine.WeightTracker.shared

        if reset {
            tracker.resetAll()
            return "All fusion engine weights have been reset to 1.0."
        }

        var report = "## Fusion Engine Weights\n\n"
        report += "| Engine | Weight | Accuracy Proxy |\n|---|---|---|\n"
        for (name, weight) in tracker.weights.sorted(by: { $0.value > $1.value }) {
            let bar = String(repeating: "█", count: Int(weight * 10))
            let accuracyHint = weight > 1.2 ? "strong" : weight > 0.8 ? "neutral" : "weak"
            report += "| \(name) | \(bar) \(BacktestingFramework.fmt(weight)) | \(accuracyHint) |\n"
        }
        report += "\nUse `fusion_weights(reset: true)` to reset all weights."

        return report
    }

    private func gamesList() -> String {
        """
        ## EZIN Games & Apps
        **Built-in app:** VINNY — the Unified Sound Intelligence Engine: 12 modules (Genesis text-to-patch AI, WaveForge wavetable lab, Organica granular, TempoShift time-warp, Earprint audio identifier, FlowState modulation, Spaceship FX rack, Hybridizer fusion, Stage performance pads, Vault presets, Vinny AI coach). I can also drive it here: `vinny_loop`, `vinny_patch`, `vinny_reference`, `vinny_stems`, `vinny_library`.
        **Arcade:**
        - Quantum Cat Box — quantum prediction and collapse
        - Frequency Frog — scales, chords and intervals
        - Fraction Fighter — math combat
        - Gravity Golf — projectile physics across planets
        - Tower of Babel — translations and false friends
        - Taxonomy Tetris — classify organisms before the stack rises
        Open the GAMES tab to play them inside the app.
        """
    }
private func newsList(args: [String: Any]) -> String {
    let feed = NewsFeedService.shared
    let limit = min((args["limit"] as? Int) ?? 10, 30)
    let items = feed.filteredNews
    guard !items.isEmpty else { return "No news articles found." }
    var result = "## Market News\n\n"
    for item in items.prefix(limit) {
        result += "• \(item.title)\n  \(item.source) · \(item.sentiment.rawValue) · \(item.impact.rawValue)\n\n"
    }
    return result
}

private func newsSearch(args: [String: Any]) -> String {
    let query = str(args, "query")
    guard !query.isEmpty else { return "Provide a search query." }
    let feed = NewsFeedService.shared
    feed.searchQuery = query
    defer { feed.searchQuery = "" }
    let matches = feed.filteredNews
    guard !matches.isEmpty else { return "No news articles match '\(query)'." }
    var result = "## News Search: '\(query)'\n\n"
    for item in matches.prefix(8) {
        result += "• \(item.title)\n  \(item.source) · \(item.sentiment.rawValue)\n\n"
    }
    return result
}

private func newsSentiment(args: [String: Any]) -> String {
    let feed = NewsFeedService.shared
    let positive = feed.newsItems.filter { $0.sentiment.score > 0 }.count
    let negative = feed.newsItems.filter { $0.sentiment.score < 0 }.count
    let neutral = feed.newsItems.filter { $0.sentiment.score == 0 }.count
    return "## News Sentiment\n\nTotal: \(feed.newsItems.count)\nBullish: \(positive)\nBearish: \(negative)\nNeutral: \(neutral)"
}

private func newsBySymbol(args: [String: Any]) -> String {
    let sym = resolveSymbol(str(args, "symbol"))
    guard !sym.isEmpty else { return "Provide a symbol." }
    let items = NewsFeedService.shared.news(for: sym)
    guard !items.isEmpty else { return "No news for \(DerivSymbols.display(sym))." }
    var result = "## News: \(DerivSymbols.display(sym))\n\n"
    for item in items.prefix(5) {
        result += "• \(item.title) (\(item.sentiment.rawValue))\n\n"
    }
    return result
}

private func newsAdd(args: [String: Any]) -> String {
    let headline = str(args, "headline")
    guard !headline.isEmpty else { return "Provide a headline." }
    let source = str(args, "source").isEmpty ? "AI Feed" : str(args, "source")
    let item = NewsFeedService.generateFromHeadline(headline, source: source)
    NewsFeedService.shared.addNews(item)
    return "Added: '\(headline.prefix(60))' — \(item.sentiment.rawValue)."
}

private func newsLatest(args: [String: Any]) -> String {
    let count = min((args["count"] as? Int) ?? 5, 15)
    let items = NewsFeedService.shared.newsItems.sorted(by: { $0.publishedAt > $1.publishedAt }).prefix(count)
    guard !items.isEmpty else { return "No news yet." }
    var result = "## Latest News\n\n"
    for item in items {
        result += "• \(item.title) — \(item.source) · \(item.impact.rawValue)\n\n"
    }
    return result
}

private func dashboardSummary() -> String {
    let journal = TradeJournalStore.shared
    let entries = journal.entries
    let open = entries.filter { $0.exitPrice == nil }
    let closed = entries.filter { $0.exitPrice != nil }
    let wins = closed.filter { entry in
        guard let exit = entry.exitPrice else { return false }
        return entry.direction == "buy" ? exit > entry.entryPrice : exit < entry.entryPrice
    }
    let wr = closed.isEmpty ? 0 : Double(wins.count) / Double(closed.count) * 100
    return """
    ## Dashboard Summary
    - Signals: \(app.signals.count) · Watchlist: \(app.settings.watchlist.count)
    - Journal: \(entries.count) entries (\(open.count) open, \(closed.count) closed)
    - Win rate: \(String(format: "%.0f", wr))% (\(wins.count)/\(closed.count))
    - Bot: \(app.bot.running ? "Running" : "Idle") · \(app.connectionState.label)
    - News: \(NewsFeedService.shared.newsItems.count) articles
    """
}

    // MARK: - AI Pipeline Tools

    private func runPipeline(args: [String: Any]) async -> String {
        let query = str(args, "query")
        guard !query.isEmpty else { return "Please provide a query to process." }
        let pipeline = AIPipelineService.shared
        let result = await pipeline.execute(query: query, availableTools: ["analyze", "signals", "price", "news_list", "backtest", "risk_plan"])
        var output = "## Pipeline Execution\n\n"
        for stage in result.stages {
            let check = stage.duration < 1.0 ? "✅" : "⏳"
            output += "\(check) \(stage.stage.rawValue) — \(String(format: "%.1f", stage.duration))s\n"
        }
        output += "\n**Total:** \(String(format: "%.1f", result.totalDuration))s · \(result.totalTokens) tokens\n"
        output += "\n**Reasoning Trace:**\n\(result.reasoningTrace.prefix(500))"
        return output
    }

    private func pipelineStatus() -> String {
        let pipeline = AIPipelineService.shared
        guard pipeline.isProcessing else { return "No pipeline currently running." }
        return "Pipeline processing: \(pipeline.currentStage) (\(String(format: "%.0f", pipeline.stageProgress * 100))%)"
    }

    private func pipelineSummary() -> String {
        return AIPipelineService.shared.pipelineSummary()
    }

    // MARK: - Chat Expansion Tools

    private func calculateTool(args: [String: Any]) -> String {
        let expression = str(args, "expression")
        guard !expression.isEmpty else { return "Provide an expression (e.g., expression='2 + 2')." }
        return ChatToolExpansion.calculate(expression: expression)
    }

    private func validateJSONTool(args: [String: Any]) -> String {
        let json = str(args, "json").isEmpty ? str(args, "text") : str(args, "json")
        guard !json.isEmpty else { return "Provide JSON to validate." }
        return ChatToolExpansion.validateJSON(json)
    }

    private func convertBaseTool(args: [String: Any]) -> String {
        let value = str(args, "value")
        let from = Int(str(args, "from")) ?? 10
        let to = Int(str(args, "to")) ?? 2
        guard !value.isEmpty else { return "Provide a value and bases (e.g., value='FF', from=16, to=10)." }
        return ChatToolExpansion.convertBase(value: value, fromBase: from, toBase: to)
    }

    private func randomNumbersTool(args: [String: Any]) -> String {
        let min = (args["min"] as? Double) ?? 0
        let max = (args["max"] as? Double) ?? 100
        let count = (args["count"] as? Int) ?? 5
        return ChatToolExpansion.randomNumber(min: min, max: max, count: count)
    }

    private func statisticsTool(args: [String: Any]) -> String {
        let raw = str(args, "numbers")
        guard !raw.isEmpty else { return "Provide comma-separated numbers (e.g., numbers='1,2,3,4,5')." }
        let numbers = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !numbers.isEmpty else { return "No valid numbers found." }
        return ChatToolExpansion.statistics(numbers: numbers)
    }

    private func linearRegressionTool(args: [String: Any]) -> String {
        guard let pointsData = args["points"] as? [[String: Double]] else {
            return "Provide points array (e.g., points=[{x:1,y:2},{x:2,y:3}])."
        }
        let points = pointsData.map { (x: $0["x"] ?? 0, y: $0["y"] ?? 0) }
        guard !points.isEmpty else { return "No valid points provided." }
        return ChatToolExpansion.linearRegression(points: points)
    }

    private func correlationTool(args: [String: Any]) -> String {
        let xRaw = str(args, "x")
        let yRaw = str(args, "y")
        let x = xRaw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let y = yRaw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard x.count == y.count, x.count >= 3 else { return "Need matching x,y datasets with 3+ points." }
        return ChatToolExpansion.correlation(x: x, y: y)
    }

    private func explainConceptTool(args: [String: Any]) -> String {
        let topic = str(args, "topic").isEmpty ? str(args, "concept") : str(args, "topic")
        guard !topic.isEmpty else { return "Provide a topic to explain (e.g., topic='RSI')." }
        return ChatToolExpansion.explainConcept(topic)
    }

    private func tradingPlanTool(args: [String: Any]) -> String {
        let style = str(args, "style").isEmpty ? "swing" : str(args, "style")
        return ChatToolExpansion.tradingPlanTemplate(style: style)
    }

    private func currencyConvertTool(args: [String: Any]) -> String {
        let amount = (args["amount"] as? Double) ?? 1.0
        let from = str(args, "from").isEmpty ? "USD" : str(args, "from")
        let to = str(args, "to").isEmpty ? "EUR" : str(args, "to")
        return ChatToolExpansion.currencyConvert(amount: amount, from: from, to: to, rates: CurrencyRates.builtIn)
    }

    private func countdownTool(args: [String: Any]) -> String {
        let event = str(args, "event").isEmpty ? "Event" : str(args, "event")
        let dateStr = str(args, "date")
        let dateFormatter = ISO8601DateFormatter()
        guard let date = dateFormatter.date(from: dateStr) else {
            return "Please provide an ISO 8601 date (e.g., date='2024-12-25T00:00:00Z')."
        }
        return ChatToolExpansion.countdown(to: date, eventName: event)
    }

    private func checklistTool(args: [String: Any]) -> String {
        let items = str(args, "items")
        guard !items.isEmpty else { return "Provide items separated by newlines." }
        return ChatToolExpansion.generateChecklist(from: items)
    }

    private func marketHealthTool() -> String {
        return ChatToolExpansion.marketHealthReport(app: app)
    }

    // MARK: - Bot Strategy Tools

    private func botStrategiesTool(args: [String: Any]) -> String {
        let filter = str(args, "filter")
        if !filter.isEmpty {
            let filtered = BotStrategyLibrary.allStrategies.filter {
                $0.name.lowercased().contains(filter.lowercased()) ||
                $0.botRiskLevel.rawValue.lowercased().contains(filter.lowercased())
            }
            guard !filtered.isEmpty else { return "No strategies matching '\(filter)'." }
            var result = "## Strategies matching '\(filter)'\n\n"
            for s in filtered {
                result += "### \(s.name)\n\(s.description)\nRisk: \(s.botRiskLevel.rawValue)\nTimeframes: \(s.timeframes.map { $0.rawValue }.joined(separator: ", "))\n\n"
            }
            return result
        }
        return BotStrategyLibrary.catalog()
    }

    private func strategyDetailTool(args: [String: Any]) -> String {
        let name = str(args, "name")
        guard !name.isEmpty, let strategy = BotStrategyLibrary.strategy(named: name) else {
            return "Strategy '\(name)' not found. Use bot_strategies to list available strategies."
        }
        var detail = "## \(strategy.name)\n\n"
        detail += "**Description:** \(strategy.description)\n"
        detail += "**Risk Level:** \(strategy.botRiskLevel.rawValue)\n"
        detail += "**Timeframes:** \(strategy.timeframes.map { $0.rawValue }.joined(separator: ", "))\n"
        detail += "**Default Parameters:**\n"
        for (key, value) in strategy.defaultParameters {
            detail += "- \(key): \(value)\n"
        }
        detail += "\n**Max Risk/Trade:** \(strategy.botRiskLevel.maxRiskPerTrade * 100)%"
        return detail
    }

    // MARK: - Enhanced Skills Tools

    private func skillsCatalogTool() -> String {
        return SkillsExtensionService.shared.catalog()
    }

    private func skillExportTool(args: [String: Any]) -> String {
        let name = str(args, "name")
        guard !name.isEmpty else { return "Provide skill name to export." }
        guard let skill = SkillsExtensionService.shared.userSkills.first(where: { $0.name.lowercased() == name.lowercased() }),
              let json = SkillsExtensionService.shared.exportSkill(skill.id) else {
            return "Skill '\(name)' not found."
        }
        return "## Exported Skill: \(skill.name)\n```json\n\(json.prefix(2000))\n```"
    }

    private func skillImportTool(args: [String: Any]) -> String {
        let json = str(args, "json").isEmpty ? str(args, "content") : str(args, "json")
        guard !json.isEmpty else { return "Provide the skill JSON to import." }
        return SkillsExtensionService.shared.importSkill(from: json)
    }

    private func skillCreateCustomTool(args: [String: Any]) -> String {
        let name = str(args, "name")
        let description = str(args, "description").isEmpty ? "Custom skill" : str(args, "description")
        let prompt = str(args, "prompt").isEmpty ? str(args, "template") : str(args, "prompt")
        guard !name.isEmpty, !prompt.isEmpty else { return "Provide name and prompt for the skill." }
        let toolsRaw = str(args, "tools")
        let tools = toolsRaw.isEmpty ? ["analyze"] : toolsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let categoryName = str(args, "category").isEmpty ? "custom" : str(args, "category")
        let category = SkillsExtensionService.SkillCategory.allCases.first { $0.rawValue.lowercased() == categoryName.lowercased() } ?? .custom
        let skill = SkillsExtensionService.shared.createSkill(name: name, category: category, description: description, promptTemplate: prompt, tools: tools)
        return "Created skill '\(skill.name)' [\(skill.category.rawValue)] with tools: \(tools.joined(separator: ", ")). Use 'skills_list' to see all skills."
    }

// MARK: - Currency Rates Helper

struct CurrencyRates {
    static let builtIn: [String: Double] = [
        "USD": 1.0, "EUR": 0.92, "GBP": 0.79, "JPY": 149.50, "CHF": 0.88,
        "CAD": 1.36, "AUD": 1.53, "NZD": 1.63, "CNY": 7.24, "INR": 83.10,
        "BRL": 4.97, "MXN": 17.15, "SGD": 1.34, "HKD": 7.82, "SEK": 10.45,
        "NOK": 10.60, "DKK": 6.88, "PLN": 4.03, "TRY": 30.20, "ZAR": 18.65
    ]
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
