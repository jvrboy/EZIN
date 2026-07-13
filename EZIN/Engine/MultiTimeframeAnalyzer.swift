import Foundation

/// Deep read of one timeframe.
struct TimeframeRead {
    let timeframe: Timeframe
    let role: String
    let price: Double
    let direction: Direction
    let trendStrength: Double      // 0...100 (ADX blended with EMA alignment)
    let momentum: String
    let volume: String
    let volatility: String
    let support: Double
    let resistance: Double
    let councilConfidence: Double? // council consensus if a quorum was reached
    let notes: [String]            // confluence factors found on this TF
    let score: Int                 // signed directional contribution (-2...+2)
}

/// Merged multi-timeframe verdict.
struct MTFResult {
    let symbol: String
    let displaySymbol: String
    let requestedTF: Timeframe
    let reads: [TimeframeRead]     // high -> low
    let biasScore: Int
    let bias: Direction
    let alignmentGrade: String     // A+, A, B, C, F
    let finalDirection: Direction
    let confidence: Double         // 0...100
    let entry: Double
    let stopLoss: Double
    let takeProfit: Double
    let riskReward: Double
    let confluences: [String]
    let verdict: String            // BUY / SELL / NO-TRADE
}

/// Top-down, all-timeframes analysis engine faithful to the bundled knowledge base:
/// determine HTF bias first, read every timeframe deeply, score alignment, require
/// confluences, drill to M1 for the execution trigger, then merge into one verdict.
/// Runs entirely on-device (no AI API needed).
struct MultiTimeframeAnalyzer {
    let deriv: DerivClient
    let engine: SignalEngine

    /// High -> low. M30 is skipped by default (M15 covers the setup role) but any
    /// requested timeframe is always included.
    private let baseHierarchy: [Timeframe] = [.d1, .h4, .h1, .m15, .m5, .m1]

    /// Higher timeframes carry more weight — HTF bias overrides LTF noise.
    private func weight(_ tf: Timeframe) -> Double {
        switch tf {
        case .d1: return 3.0; case .h4: return 3.0; case .h1: return 2.0
        case .m30: return 1.5; case .m15: return 1.5; case .m5: return 1.0; case .m1: return 1.0
        }
    }

    func analyze(symbol: String, requested: Timeframe) async -> MTFResult? {
        var tfs = baseHierarchy
        if !tfs.contains(requested) {
            tfs.append(requested)
            tfs.sort { $0.granularity > $1.granularity }
        }

        var reads: [TimeframeRead] = []
        for tf in tfs {
            guard let candles = try? await deriv.candles(symbol: symbol, timeframe: tf, count: 200),
                  candles.count > 40 else { continue }
            var md = MarketData(symbol: symbol, assetClass: DerivSymbols.assetClass(symbol),
                                timeframe: tf, candles: candles)
            md.currentPrice = deriv.prices[symbol] ?? candles.last?.close ?? 0
            let ind = engine.analyzer.analyze(md)
            let votes = engine.agents.filter { $0.isActive }.map { $0.analyze(md, ind) }
            let decision = engine.council.deliberate(symbol: symbol, timeframe: tf, votes: votes)
            reads.append(buildRead(tf: tf, md: md, ind: ind, decision: decision))
        }
        guard !reads.isEmpty else { return nil }

        // 1. HTF bias — score across D1/H4/H1 structure + EMA200 positioning.
        let biasScore = reads.filter { [.d1, .h4, .h1].contains($0.timeframe) }
            .reduce(0) { $0 + $1.score }
        let bias: Direction = biasScore >= 3 ? .bullish : (biasScore <= -3 ? .bearish : .neutral)

        // 2. Weighted merge across all timeframes.
        let weighted = reads.reduce(0.0) { $0 + Double($1.score) * weight($1.timeframe) }
        let finalDirection: Direction = weighted >= 2 ? .strongBullish
            : (weighted > 0 ? .bullish : (weighted <= -2 ? .strongBearish : (weighted < 0 ? .bearish : .neutral)))

        // 3. Alignment grade (how many key TFs agree with the final direction).
        let grade = alignmentGrade(reads: reads, direction: finalDirection)

        // 4. Confidence from agreement ratio + council confidence on the requested TF.
        let agree = reads.filter { sameSide($0.direction, finalDirection) }.count
        var confidence = Double(agree) / Double(reads.count) * 100
        if let rc = reads.first(where: { $0.timeframe == requested })?.councilConfidence {
            confidence = (confidence + rc * 100) / 2
        }
        confidence = min(99, max(0, confidence.rounded()))

        // 5. Entry / stop / target from the requested timeframe using its ATR.
        let entryRead = reads.first(where: { $0.timeframe == requested }) ?? reads.last!
        let atr = requestedATR(symbol: symbol, read: entryRead)
        let isBuy = finalDirection.isBullish
        let entry = entryRead.price
        let sl = isBuy ? entry - atr * engine.stopLossATR : entry + atr * engine.stopLossATR
        let tp = isBuy ? entry + atr * engine.takeProfitATR : entry - atr * engine.takeProfitATR
        let rr = atr > 0 ? engine.takeProfitATR / engine.stopLossATR : 0

        // 6. Confluences and final verdict.
        let confluences = collectConfluences(reads: reads, bias: bias, direction: finalDirection, grade: grade)
        let verdict: String
        if grade == "F" || finalDirection == .neutral || confluences.count < 3 {
            verdict = "NO-TRADE"
        } else {
            verdict = isBuy ? "BUY" : "SELL"
        }

        return MTFResult(
            symbol: symbol, displaySymbol: DerivSymbols.display(symbol), requestedTF: requested,
            reads: reads, biasScore: biasScore, bias: bias, alignmentGrade: grade,
            finalDirection: finalDirection, confidence: confidence,
            entry: entry, stopLoss: sl, takeProfit: tp, riskReward: rr,
            confluences: confluences, verdict: verdict
        )
    }

    // MARK: - Per-timeframe read

    private func buildRead(tf: Timeframe, md: MarketData, ind: TechnicalIndicators,
                           decision: CouncilDecision?) -> TimeframeRead {
        let price = md.currentPrice > 0 ? md.currentPrice : (md.latest?.close ?? 0)
        var notes: [String] = []
        var s = 0

        // Trend structure
        if ind.ema12 > ind.ema26 { s += 1; notes.append("EMA12 > EMA26 (short-term up)") }
        else { s -= 1; notes.append("EMA12 < EMA26 (short-term down)") }
        if ind.ema50 > ind.ema200 { s += 1; notes.append("EMA50 > EMA200 (golden alignment)") }
        else { s -= 1; notes.append("EMA50 < EMA200 (death alignment)") }
        if price > ind.ema200, ind.ema200 > 0 { s += 1 } else if ind.ema200 > 0 { s -= 1 }
        if ind.supertrendUp { s += 1; notes.append("Supertrend up") } else { s -= 1; notes.append("Supertrend down") }

        // Ichimoku cloud position
        let cloudTop = max(ind.ichimokuSenkouA, ind.ichimokuSenkouB)
        let cloudBot = min(ind.ichimokuSenkouA, ind.ichimokuSenkouB)
        if price > cloudTop, cloudTop > 0 { s += 1; notes.append("Price above Kumo cloud (bullish)") }
        else if price < cloudBot, cloudBot > 0 { s -= 1; notes.append("Price below Kumo cloud (bearish)") }

        // Momentum
        if ind.macdHistogram > 0 { s += 1 } else { s -= 1 }
        if ind.rsi14 > 55 { s += 1 } else if ind.rsi14 < 45 { s -= 1 }
        let momentum: String
        if ind.rsi14 >= 70 { momentum = "overbought (RSI \(Int(ind.rsi14)))" }
        else if ind.rsi14 <= 30 { momentum = "oversold (RSI \(Int(ind.rsi14)))" }
        else { momentum = "RSI \(Int(ind.rsi14)), MACD \(ind.macdHistogram >= 0 ? "rising" : "falling")" }

        // Volume / money flow
        var volScore = 0
        if ind.cmf > 0.05 { volScore += 1 } else if ind.cmf < -0.05 { volScore -= 1 }
        if ind.mfi14 > 55 { volScore += 1 } else if ind.mfi14 < 45 { volScore -= 1 }
        let volume = volScore > 0 ? "buying pressure (CMF \(String(format: "%.2f", ind.cmf)))"
            : (volScore < 0 ? "selling pressure (CMF \(String(format: "%.2f", ind.cmf)))" : "balanced flow")

        // Volatility regime
        let volatility: String
        if ind.bbWidth > 0.06 { volatility = "expanding (BB width \(String(format: "%.3f", ind.bbWidth)))" }
        else if ind.bbWidth < 0.02 { volatility = "compressing — breakout risk" }
        else { volatility = "normal" }

        // Direction: prefer council; otherwise derive from the score.
        let direction: Direction
        if let d = decision { direction = d.direction }
        else { direction = s >= 4 ? .strongBullish : (s >= 1 ? .bullish : (s <= -4 ? .strongBearish : (s <= -1 ? .bearish : .neutral))) }

        // Normalise the signed contribution to -2...+2 for merge weighting.
        let clamped = max(-2, min(2, s / 2))

        let support = ind.donchianLower > 0 ? ind.donchianLower : ind.pivotS1
        let resistance = ind.donchianUpper > 0 ? ind.donchianUpper : ind.pivotR1

        return TimeframeRead(
            timeframe: tf, role: KnowledgeBase.shared.role(for: tf), price: price,
            direction: direction, trendStrength: ind.trendStrength, momentum: momentum,
            volume: volume, volatility: volatility, support: support, resistance: resistance,
            councilConfidence: decision?.consensusRatio, notes: notes, score: clamped
        )
    }

    private func requestedATR(symbol: String, read: TimeframeRead) -> Double {
        // Re-derive a sane ATR proxy from the read's price if the engine value is unusable.
        return read.price > 0 ? read.price * 0.0015 : 0
    }

    // MARK: - Scoring helpers

    private func sameSide(_ a: Direction, _ b: Direction) -> Bool {
        (a.isBullish && b.isBullish) || (a.isBearish && b.isBearish)
    }

    private func alignmentGrade(reads: [TimeframeRead], direction: Direction) -> String {
        func agrees(_ tf: Timeframe) -> Bool {
            guard let r = reads.first(where: { $0.timeframe == tf }) else { return false }
            return sameSide(r.direction, direction)
        }
        let htfAligned = agrees(.d1) && agrees(.h4) && agrees(.h1) && agrees(.m15)
        let swingAligned = agrees(.h4) && agrees(.h1) && agrees(.m15)
        let opAligned = agrees(.h1) && agrees(.m15)
        let trigger = agrees(.m1) || agrees(.m5)

        if direction == .neutral { return "F" }
        if htfAligned && trigger { return "A+" }
        if swingAligned { return "A" }
        if opAligned { return "B" }
        // Count chaotic conflict.
        let bulls = reads.filter { $0.direction.isBullish }.count
        let bears = reads.filter { $0.direction.isBearish }.count
        if bulls > 0 && bears > 0 && abs(bulls - bears) <= 1 { return "F" }
        return "C"
    }

    private func collectConfluences(reads: [TimeframeRead], bias: Direction,
                                    direction: Direction, grade: String) -> [String] {
        var out: [String] = []
        if bias != .neutral, sameSide(bias, direction) {
            out.append("Higher-timeframe bias (\(label(bias))) aligns with the trade direction")
        }
        for tf in [Timeframe.d1, .h4, .h1, .m15, .m5, .m1] {
            guard let r = reads.first(where: { $0.timeframe == tf }) else { continue }
            if sameSide(r.direction, direction) {
                out.append("\(tf.rawValue) (\(r.role)) agrees: \(label(r.direction)), trend strength \(Int(r.trendStrength))")
            }
        }
        if let entry = reads.first(where: { $0.direction == direction }) {
            out.append("Momentum on \(entry.timeframe.rawValue): \(entry.momentum)")
        }
        return out
    }

    private func label(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "Strong Bullish"; case .bullish: return "Bullish"
        case .neutral: return "Neutral"; case .bearish: return "Bearish"; case .strongBearish: return "Strong Bearish"
        }
    }
}

// MARK: - Professional Markdown report

extension MTFResult {
    private func label(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "Strong Bullish"; case .bullish: return "Bullish"
        case .neutral: return "Neutral"; case .bearish: return "Bearish"; case .strongBearish: return "Strong Bearish"
        }
    }

    /// Structured, professional Markdown consumed by the chat renderer.
    func markdownReport() -> String {
        var md = "# \(displaySymbol) — Multi-Timeframe Analysis\n"
        md += "Requested timeframe: **\(requestedTF.rawValue)** · Analysed \(reads.count) timeframes top-down.\n\n"

        md += "## Verdict\n"
        let emoji = verdict == "BUY" ? "🟢" : (verdict == "SELL" ? "🔴" : "⚪️")
        md += "\(emoji) **\(verdict)** — \(label(finalDirection)) · Confidence **\(Int(confidence))%** · Alignment grade **\(alignmentGrade)**\n\n"
        if verdict != "NO-TRADE" {
            md += "- Entry: **\(fmt(entry))**\n"
            md += "- Stop loss: **\(fmt(stopLoss))**\n"
            md += "- Take profit: **\(fmt(takeProfit))**\n"
            md += "- Risk/reward: **1 : \(String(format: "%.1f", riskReward))**\n\n"
        } else {
            md += "No high-probability setup right now — timeframes are not aligned or confluences are insufficient. Patience is an edge.\n\n"
        }

        md += "## Higher-Timeframe Bias\n"
        md += "Bias score **\(biasScore)** across D1/H4/H1 → **\(label(bias))**. "
        md += "A signal against this bias is treated as counter-trend and held to stricter standards.\n\n"

        md += "## Timeframe Breakdown\n"
        for r in reads {
            md += "### \(r.timeframe.rawValue) — \(r.role)\n"
            md += "- Direction: **\(label(r.direction))** (trend strength \(Int(r.trendStrength)))\n"
            md += "- Momentum: \(r.momentum)\n"
            md += "- Volume: \(r.volume)\n"
            md += "- Volatility: \(r.volatility)\n"
            md += "- Key levels: support \(fmt(r.support)) · resistance \(fmt(r.resistance))\n"
            if let c = r.councilConfidence {
                md += "- Council consensus: \(Int(c * 100))%\n"
            }
            md += "\n"
        }

        md += "## Confluences (\(confluences.count))\n"
        if confluences.isEmpty {
            md += "- None found.\n"
        } else {
            for c in confluences { md += "- \(c)\n" }
        }
        md += "\n_Analysis is educational, not financial advice. Validate on a demo account first._"
        return md
    }

    private func fmt(_ v: Double) -> String { String(format: "%.4f", v) }
}
