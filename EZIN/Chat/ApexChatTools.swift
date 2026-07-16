import Foundation

/// APEX chat tools — exposes the second-generation backend engines to the assistant.
extension ToolRegistry {

    func masterConfluenceTool(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty else { return "Missing 'symbol' parameter." }
        app.deriv.subscribeTicks(symbol)
        guard let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need at least 30 cached candles for \(DerivSymbols.display(symbol)). Open it on the Chart tab first, then ask again."
        }
        return ApexBackend.masterReport(md, symbol: DerivSymbols.display(symbol), engine: app.engine)
    }

    func patternScanTool(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need a symbol with at least 30 cached candles (open it on Chart first)."
        }
        return ApexBackend.patternReport(md, symbol: DerivSymbols.display(symbol))
    }

    func marketProfileTool(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need a symbol with at least 30 cached candles (open it on Chart first)."
        }
        return ApexBackend.profileReport(md, symbol: DerivSymbols.display(symbol))
    }

    func liquidityMapTool(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need a symbol with at least 30 cached candles (open it on Chart first)."
        }
        return ApexBackend.liquidityReport(md, symbol: DerivSymbols.display(symbol))
    }

    func rangeForecastTool(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need a symbol with at least 30 cached candles (open it on Chart first)."
        }
        return ApexBackend.rangeReport(md, symbol: DerivSymbols.display(symbol))
    }

    func entropyAnalysisTool(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty, let md = marketData(for: symbol, timeframe: timeframe) else {
            return "Need a symbol with at least 30 cached candles (open it on Chart first)."
        }
        return ApexBackend.entropyReport(md, symbol: DerivSymbols.display(symbol))
    }

    /// Scan multiple symbols (or the whole watchlist) and rank them by master confluence.
    func symbolScannerTool(_ args: [String: Any]) -> String {
        let timeframe = resolveTF(str(args, "timeframe"))
        var symbols: [String] = []
        if let raw = args["symbols"] as? String, !raw.isEmpty {
            symbols = raw.split(separator: ",").map { resolveSymbol(String($0).trimmingCharacters(in: .whitespaces)) }
        } else if let list = args["symbols"] as? [String] {
            symbols = list.map { resolveSymbol($0) }
        } else {
            symbols = SettingsStore.shared.watchlist
        }
        guard !symbols.isEmpty else { return "No symbols to scan — pass 'symbols' or build a watchlist." }
        let hits = ApexBackend.scan(symbols: symbols) { marketData(for: $0, timeframe: timeframe) }
        guard !hits.isEmpty else {
            return "Nothing actionable across \(symbols.count) symbols right now (or candles not cached — open them on Chart first)."
        }
        var s = "## Symbol Scanner — \(timeframe.rawValue)\n\n"
        s += "| Symbol | Verdict | Score | Conf | Note |\n|---|---|---|---|---|\n"
        for h in hits.prefix(10) {
            s += "| \(DerivSymbols.display(h.symbol)) | \(AdvancedBackend.dir(h.verdict)) | \(String(format: "%.2f", h.score)) | \(Int(h.confidence * 100))% | \(h.note) |\n"
        }
        s += "\nRanked by absolute master-confluence score. Deepest audit per symbol: `master_confluence`."
        return s
    }
}
