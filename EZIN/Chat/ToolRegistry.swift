import Foundation

/// Executes the in-app and explicitly configured MCP tools the chat agent can call.
@MainActor
struct ToolRegistry {
    let app: AppState

    func run(_ name: String, args: [String: Any]) async -> String {
        switch name {
        case "analyze": return await analyze(args)
        case "signals": return signals()
        case "price": return price(args)
        case "instruments": return instruments(args)
        case "history": return history()
        case "place_trade": return await placeTrade(args)
        case "indicators": return await PipelineExecutor(app: app).run(id: "full_technical_analysis", args: args)
        case "agents", "council": return await PipelineExecutor(app: app).run(id: "council_scan", args: args)
        case "pipeline": return await PipelineExecutor(app: app).run(id: str(args, "name"), args: args)
        case "pipelines": return await PipelineExecutor(app: app).run(id: "list", args: args)
        case "web_scrape": return await webScrape(args)
        case "workspace_write": return await workspaceWrite(args)
        case "workspace_read": return await workspaceRead(args)
        case "workspace_list": return await workspaceList(args)
        case "workspace_delete": return await workspaceDelete(args)
        case "workspace_export": return await workspaceExport(args)
        case "create_file", "create_text", "create_markdown", "create_csv", "create_json", "create_wav":
            return createArtifact(tool: name, args: args)
        case "tools": return capabilityList()
        case "mcp": return await mcp(args)
        default: return "Unknown tool: \(name). Call tools to see supported capabilities."
        }
    }

    // MARK: - Arguments

    private func str(_ args: [String: Any], _ key: String) -> String { args[key] as? String ?? "" }
    private func bool(_ args: [String: Any], _ key: String, fallback: Bool = false) -> Bool {
        if let value = args[key] as? Bool { return value }
        switch str(args, key).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return fallback
        }
    }
    private func number(_ args: [String: Any], _ key: String, fallback: Double = 0) -> Double {
        if let value = args[key] as? Double { return value }
        if let value = args[key] as? Int { return Double(value) }
        return Double(str(args, key)) ?? fallback
    }

    private func resolveSymbol(_ value: String) -> String {
        if DerivSymbols.all.contains(value) { return value }
        if let exact = DerivSymbols.all.first(where: { DerivSymbols.display($0).caseInsensitiveCompare(value) == .orderedSame }) { return exact }
        if let partial = DerivSymbols.all.first(where: { !value.isEmpty && DerivSymbols.display($0).localizedCaseInsensitiveContains(value) }) { return partial }
        return value
    }

    private func resolveTF(_ value: String) -> Timeframe { Timeframe(rawValue: value) ?? .m5 }

    // MARK: - Market tools

    /// Deep multi-timeframe analysis composed from live candle requests and the production council.
    private func analyze(_ args: [String: Any]) async -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let timeframe = resolveTF(str(args, "timeframe"))
        guard !symbol.isEmpty else { return "Please specify a symbol." }
        let mtf = MultiTimeframeEngine(deriv: app.deriv, engine: app.engine)
        guard let report = await mtf.analyze(symbol: symbol, requested: timeframe) else {
            return "No market data is available for \(DerivSymbols.display(symbol)). Check the Deriv connection and symbol."
        }
        return report.markdown()
    }

    private func signals() -> String {
        guard !app.signals.isEmpty else { return "No live signals right now." }
        return app.signals.prefix(12).map {
            "\($0.displayPair): \($0.isBuy ? "BUY" : "SELL") \(Int($0.confidence))% (\($0.strategy), \($0.timeframe.rawValue))"
        }.joined(separator: "\n")
    }

    private func price(_ args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        if let value = app.deriv.prices[symbol] { return "\(DerivSymbols.display(symbol)) = \(value)" }
        return "No live price for \(DerivSymbols.display(symbol)) yet. Open the instrument or check the connection."
    }

    private func instruments(_ args: [String: Any]) -> String {
        let query = str(args, "query").lowercased()
        let matches = DerivSymbols.all.filter {
            query.isEmpty || DerivSymbols.display($0).lowercased().contains(query) || $0.lowercased().contains(query)
        }
        guard !matches.isEmpty else { return "No instruments match '\(query)'." }
        return matches.prefix(50).map { "\(DerivSymbols.display($0)) [\($0)]" }.joined(separator: "\n")
    }

    private func history() -> String {
        if app.deriv.authorized, !app.history.isEmpty {
            let net = app.history.reduce(0) { $0 + $1.profit }
            return "\(app.history.count) closed trades, net P&L \(String(format: "%.2f", net)) \(app.deriv.currency)."
        }
        let signals = SignalHistoryStore.shared.signals
        guard !signals.isEmpty else { return "No trade or signal history yet." }
        return "\(signals.count) generated signals logged. Recent: " + signals.prefix(8).map {
            "\($0.displayPair) \($0.isBuy ? "BUY" : "SELL")"
        }.joined(separator: ", ")
    }

    private func placeTrade(_ args: [String: Any]) async -> String {
        guard ChatConfigStore.shared.config.allowTrading else {
            return "Trading from chat is disabled. Enable Allow trading from chat in Chat settings first."
        }
        guard app.deriv.authorized else {
            return "Not authorized — add your Deriv API token in Settings to place real trades."
        }
        let symbol = resolveSymbol(str(args, "symbol"))
        guard !symbol.isEmpty else { return "Please specify a valid symbol." }
        let direction = str(args, "direction").lowercased()
        let up = direction.contains("buy") || direction.contains("up") || direction.contains("long")
        let stake = number(args, "stake", fallback: app.botConfig.config.fixedLotSize)
        guard stake > 0 else { return "Stake must be greater than zero." }
        do {
            let proposal = try await app.deriv.proposal(
                symbol: symbol,
                up: up,
                stake: stake,
                multiplier: app.botConfig.config.multiplier,
                currency: app.deriv.currency,
                stopLoss: nil,
                takeProfit: nil
            )
            let contractID = try await app.deriv.buy(proposalId: proposal.id, price: proposal.price)
            return "Placed \(up ? "BUY" : "SELL") on \(DerivSymbols.display(symbol)), stake \(stake) \(app.deriv.currency). Contract #\(contractID)."
        } catch {
            return "Trade failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Public web extraction

    private func webScrape(_ args: [String: Any]) async -> String {
        do {
            let result = try await WebScraper.shared.scrape(
                url: str(args, "url"),
                maxCharacters: Int(number(args, "max_characters", fallback: 20_000))
            )
            var output = "# \(result.title)\nSource: \(result.finalURL) · HTTP \(result.statusCode)"
            if !result.description.isEmpty { output += "\n\n\(result.description)" }
            output += "\n\n\(result.text)"
            if bool(args, "include_links"), !result.links.isEmpty {
                output += "\n\n## Links\n" + result.links.map { "- \($0)" }.joined(separator: "\n")
            }
            return output
        } catch {
            return "Web scrape failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Agent workspace

    private func workspaceWrite(_ args: [String: Any]) async -> String {
        let path = str(args, "path")
        let content = str(args, "content")
        let data: Data?
        if str(args, "encoding").lowercased() == "base64" {
            data = Data(base64Encoded: content, options: [.ignoreUnknownCharacters])
        } else {
            data = content.data(using: .utf8)
        }
        guard let data else { return "Workspace write failed: invalid content encoding." }
        do {
            let entry = try await AgentWorkspace.shared.write(path: path, data: data, overwrite: bool(args, "overwrite", fallback: true))
            return "Created workspace file \(entry.path) (\(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)))."
        } catch {
            return "Workspace write failed: \(error.localizedDescription)"
        }
    }

    private func workspaceRead(_ args: [String: Any]) async -> String {
        do {
            let data = try await AgentWorkspace.shared.read(path: str(args, "path"))
            if str(args, "encoding").lowercased() == "base64" { return data.base64EncodedString() }
            guard let text = String(data: data, encoding: .utf8) else {
                return "This is a binary file. Read it again with encoding=base64."
            }
            return text
        } catch {
            return "Workspace read failed: \(error.localizedDescription)"
        }
    }

    private func workspaceList(_ args: [String: Any]) async -> String {
        do {
            let entries = try await AgentWorkspace.shared.list(
                path: str(args, "path"),
                recursive: bool(args, "recursive", fallback: true),
                limit: Int(number(args, "limit", fallback: 200))
            )
            guard !entries.isEmpty else { return "The agent workspace is empty." }
            return entries.map {
                "\($0.isDirectory ? "DIR" : "FILE") \($0.path)\($0.isDirectory ? "" : " · " + ByteCountFormatter.string(fromByteCount: $0.byteSize, countStyle: .file))"
            }.joined(separator: "\n")
        } catch {
            return "Workspace list failed: \(error.localizedDescription)"
        }
    }

    private func workspaceDelete(_ args: [String: Any]) async -> String {
        guard bool(args, "confirm") else { return "Deletion requires confirm=true." }
        do {
            try await AgentWorkspace.shared.delete(path: str(args, "path"))
            return "Deleted workspace item \(str(args, "path"))."
        } catch {
            return "Workspace delete failed: \(error.localizedDescription)"
        }
    }

    private func workspaceExport(_ args: [String: Any]) async -> String {
        do {
            let data = try await AgentWorkspace.shared.read(path: str(args, "path"))
            var artifactArgs = args
            artifactArgs["content"] = data.base64EncodedString()
            artifactArgs["encoding"] = "base64"
            if str(artifactArgs, "name").isEmpty {
                artifactArgs["name"] = URL(fileURLWithPath: str(args, "path")).lastPathComponent
            }
            return createArtifact(tool: "create_file", args: artifactArgs)
        } catch {
            return "Workspace export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Downloadable artifacts

    private func createArtifact(tool: String, args: [String: Any]) -> String {
        let content = str(args, "content")
        let data: Data?
        if str(args, "encoding").lowercased() == "base64" {
            data = Data(base64Encoded: content, options: [.ignoreUnknownCharacters])
        } else {
            data = content.data(using: .utf8)
        }
        guard let data else { return "File creation failed: invalid content encoding." }
        guard data.count <= 5 * 1024 * 1024 else { return "File creation failed: files are limited to 5 MB." }

        let fallbackExtension: String
        switch tool {
        case "create_markdown": fallbackExtension = "md"
        case "create_csv": fallbackExtension = "csv"
        case "create_json": fallbackExtension = "json"
        case "create_wav": fallbackExtension = "wav"
        default: fallbackExtension = "txt"
        }
        var name = sanitizedFilename(str(args, "name"))
        if name.isEmpty { name = "ezin-file-\(Int(Date().timeIntervalSince1970)).\(fallbackExtension)" }
        if URL(fileURLWithPath: name).pathExtension.isEmpty { name += ".\(fallbackExtension)" }

        var finalData = data
        if tool == "create_json", str(args, "encoding").lowercased() != "base64",
           let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            finalData = pretty
        }

        let destination = FileStore.shared.artifactsDir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: FileStore.shared.artifactsDir, withIntermediateDirectories: true)
            try finalData.write(to: destination, options: .atomic)
            let artifact = Artifact(
                name: name,
                relativePath: "Artifacts/\(name)",
                kind: destination.pathExtension.lowercased(),
                byteSize: Int64(finalData.count)
            )
            ArtifactStore.shared.add(artifact)
            return "Created \(name) (\(ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file)))."
        } catch {
            return "File creation failed: \(error.localizedDescription)"
        }
    }

    private func sanitizedFilename(_ value: String) -> String {
        let last = URL(fileURLWithPath: value).lastPathComponent
        let invalid = CharacterSet(charactersIn: "/\\:\0").union(.newlines).union(.controlCharacters)
        return last.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Integrations and discovery

    private func mcp(_ args: [String: Any]) async -> String {
        let server = str(args, "server")
        let tool = str(args, "tool")
        let toolArgs = args["args"] as? [String: Any] ?? [:]
        guard let connector = MCPStore.shared.byServerName(server) else {
            return "No enabled MCP connector named '\(server)'. Add or enable one in Settings → MCP Connectors."
        }
        do { return try await MCPClient(connector: connector).callTool(tool, args: toolArgs) }
        catch { return "MCP call failed: \(error.localizedDescription)" }
    }

    private func capabilityList() -> String {
        [
            "analyze(symbol,timeframe) — live multi-timeframe report",
            "indicators(symbol,timeframe) — full indicator and council snapshot",
            "agents(symbol,timeframe) — all active agent votes",
            "pipeline(name,...) / pipelines — execute or list backend pipelines",
            "signals / price / instruments / history — real-time app data",
            "web_scrape(url,max_characters,include_links) — bounded public-page extraction",
            "workspace_write/read/list/delete/export — path-confined agent file workspace",
            "create_file/text/markdown/csv/json/wav — downloadable artifacts; binary uses base64",
            "place_trade — guarded Deriv execution",
            "mcp(server,tool,args) — explicitly configured external tools"
        ].joined(separator: "\n")
    }
}
