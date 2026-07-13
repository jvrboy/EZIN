import Foundation

/// Executes the in-app + MCP tools the chat agent can call.
@MainActor
struct ToolRegistry {
    let app: AppState

    func run(_ name: String, args: [String: Any]) async -> String {
        switch name {
        case "analyze":     return await analyze(args)
        case "signals":     return signals()
        case "price":       return price(args)
        case "instruments": return instruments(args)
        case "history":     return history()
        case "place_trade": return await placeTrade(args)
        case "mcp":         return await mcp(args)
        default:            return "Unknown tool: \(name)"
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

    private func resolveTF(_ s: String) -> Timeframe { Timeframe(rawValue: s) ?? .m1 }

    // MARK: tools
    private func analyze(_ args: [String: Any]) async -> String {
        let sym = resolveSymbol(str(args, "symbol"))
        let tf = resolveTF(str(args, "timeframe"))
        guard !sym.isEmpty else { return "Please specify a symbol." }
        guard let candles = try? await app.deriv.candles(symbol: sym, timeframe: tf, count: 200), candles.count > 40 else {
            return "No market data available for \(sym)."
        }
        var md = MarketData(symbol: sym, assetClass: DerivSymbols.assetClass(sym), timeframe: tf, candles: candles)
        md.currentPrice = app.deriv.prices[sym] ?? candles.last?.close ?? 0
        let ind = app.engine.analyzer.analyze(md)
        let votes = app.engine.agents.filter { $0.isActive }.map { $0.analyze(md, ind) }
        let decision = app.engine.council.deliberate(symbol: sym, timeframe: tf, votes: votes)
        var out = "Analysis \(DerivSymbols.display(sym)) [\(tf.rawValue)] price \(String(format: "%.4f", md.currentPrice))\n"
        out += String(format: "RSI14 %.0f, MACD %.4f, ADX %.0f, StochK %.0f, CCI %.0f\n", ind.rsi14, ind.macdHistogram, ind.adx, ind.stochK, ind.cci20)
        out += "EMA12\(ind.ema12 > ind.ema26 ? ">" : "<")EMA26, Supertrend \(ind.supertrendUp ? "up" : "down"), Ichimoku \(ind.ichimokuTenkan > ind.ichimokuKijun ? "bull" : "bear"), VWAP \(md.currentPrice > ind.vwap ? "above" : "below")\n"
        if let d = decision {
            out += "Council: \(d.direction) · confidence \(Int(d.consensusRatio * 100))% · strength \(d.strength) (\(votes.count) agents)."
        } else {
            out += "Council: no consensus yet."
        }
        return out
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
}
