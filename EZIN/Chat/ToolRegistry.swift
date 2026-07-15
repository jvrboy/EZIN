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
}
