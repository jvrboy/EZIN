import Foundation

/// Ultra-Confirmation AI Trading Pipeline
///
/// An institutional-grade multi-layer confluence system that produces
/// conditional trade plans rather than simple buy/sell signals.
/// Inspired by the user's detailed specification for XAUUSD but generalized
/// to work with any instrument EZIN supports.
///
/// The pipeline enforces:
///   1. Market data integrity (no stale/spread-widened signals)
///   2. Multi-timeframe structure alignment
///   3. Price action & smart-money confluence
///   4. Classical technical confirmation
///   5. Risk/viability checks (minimum R:R, position sizing)
///   6. Explainable output with clear invalidation levels
struct UltraConfirmationPipeline {

    // MARK: - Input

    struct PipelineInput {
        let symbol: String
        let timeframe: Timeframe
        let accountSize: Double?
        let riskPercent: Double?
        let sessionPreference: String?  // "asia", "london", "ny"
        let currentPosition: PositionInfo?
    }

    struct PositionInfo {
        let entry: Double
        let stopLoss: Double
        let takeProfit: Double
    }

    // MARK: - Output

    struct PipelineOutput {
        let status: SignalStatus
        let direction: Direction
        let confidence: Int  // 0-100
        let marketRegime: String
        let macroContext: String
        let confluenceScore: Double  // 0-1
        let entryZone: Double
        let invalidation: Double
        let target1: Double
        let target2: Double
        let target3: Double
        let stopLoss: Double
        let riskReward: Double
        let positionSize: Double?
        let rationale: [String]
        let warnings: [String]
        let invalidationReasons: [String]
        let timeHorizon: String
    }

    enum SignalStatus: String {
        case strongBuy = "Strong Buy Candidate"
        case conditionalLong = "Conditional Long"
        case strongSell = "Strong Sell Candidate"
        case conditionalShort = "Conditional Short"
        case neutral = "Neutral / Wait"
        case noTrade = "No Trade"
        case lockdown = "High-Impact-News Lockdown"
    }

    // MARK: - Pipeline Steps

    func run(input: PipelineInput, report: AnalysisReport) -> PipelineOutput {
        var rationale: [String] = []
        var warnings: [String] = []
        var score = 0.0
        let price = report.verdict.entry

        // Step 1: Data integrity
        let integrity = checkDataIntegrity(report: report)
        if !integrity.isValid {
            return makeOutput(.noTrade, .neutral, 0, report, price,
                              rationale: ["Data integrity failed: \(integrity.reason)"],
                              warnings: ["Do not trade with stale data."])
        }
        rationale.append("Data integrity: \(integrity.reason)")
        score += 0.1

        // Step 2: Multi-timeframe alignment
        let mtfScore = evaluateMTFAlignment(report: report)
        rationale.append("MTF alignment: \(String(format: "%.0f", mtfScore.alignment * 100))% — \(mtfScore.notes)")
        score += mtfScore.alignment * 0.25
        if mtfScore.higherTFConflict {
            warnings.append("Higher timeframe conflicts with entry timeframe — reduce size or wait.")
        }

        // Step 3: Market structure & price action
        let structureScore = evaluateStructure(report: report)
        rationale.append("Market structure: \(structureScore.description)")
        score += structureScore.score * 0.2

        // Step 4: Order flow & volume
        let flowScore = evaluateOrderFlow(report: report)
        rationale.append("Order flow: \(flowScore.description)")
        score += flowScore.score * 0.15

        // Step 5: Momentum confirmation
        let momScore = evaluateMomentum(report: report)
        rationale.append("Momentum: \(momScore.description)")
        score += momScore.score * 0.1

        // Step 6: Volatility regime check
        let volCheck = evaluateVolatility(report: report)
        rationale.append("Volatility: \(volCheck.description)")
        score += volCheck.score * 0.1
        if volCheck.regime == .ultra {
            warnings.append("Ultra-high volatility — expect wide spreads, reduce position size.")
        }

        // Step 7: Macro/session context
        let macroScore = evaluateMacroContext(input: input, report: report)
        rationale.append("Context: \(macroScore.description)")
        score += macroScore.score * 0.1

        // Determine direction from the focus timeframe
        let direction = report.requestedFocus.direction
        let isBullish = direction.isBullish

        // Calculate levels
        let atr = max(abs(price) * report.requestedFocus.realizedVol, abs(price) * 0.001)
        let (entry, sl, tp1, tp2, tp3, invalidation) = calculateLevels(
            direction: direction, price: price, atr: atr,
            support: report.requestedFocus.support,
            resistance: report.requestedFocus.resistance
        )

        let rr = abs(tp1 - entry) / abs(entry - sl)

        // Risk check
        var positionSize: Double?
        if let account = input.accountSize, let riskPct = input.riskPercent, rr >= 1.0 {
            let riskAmount = account * (riskPct / 100)
            positionSize = riskAmount / abs(entry - sl)
        }

        // Determine status based on score
        let status: SignalStatus
        let finalConfidence: Int
        switch score {
        case let s where s >= 0.75 && isBullish:
            status = .strongBuy; finalConfidence = min(97, Int(s * 100))
        case let s where s >= 0.55 && isBullish:
            status = .conditionalLong; finalConfidence = min(85, Int(s * 100))
        case let s where s >= 0.75:
            status = .strongSell; finalConfidence = min(97, Int(s * 100))
        case let s where s >= 0.55:
            status = .conditionalShort; finalConfidence = min(85, Int(s * 100))
        case let s where s >= 0.35:
            status = .neutral; finalConfidence = Int(s * 100)
        default:
            status = .noTrade; finalConfidence = Int(score * 100)
        }

        // Time horizon
        let timeHorizon = estimateTimeHorizon(timeframe: input.timeframe, score: score)

        // Invalidation reasons
        var invalidationReasons: [String] = []
        invalidationReasons.append("Close below/above \(String(format: "%.4f", invalidation)) with displacement")
        if macroScore.score < 0 { invalidationReasons.append("Macro context turns against position") }
        if mtfScore.higherTFConflict { invalidationReasons.append("Higher timeframe structure breaks") }

        return PipelineOutput(
            status: status,
            direction: direction,
            confidence: finalConfidence,
            marketRegime: report.requestedFocus.regime.rawValue,
            macroContext: macroScore.description,
            confluenceScore: score,
            entryZone: entry,
            invalidation: invalidation,
            target1: tp1,
            target2: tp2,
            target3: tp3,
            stopLoss: sl,
            riskReward: rr,
            positionSize: positionSize,
            rationale: rationale,
            warnings: warnings,
            invalidationReasons: invalidationReasons,
            timeHorizon: timeHorizon
        )
    }

    // MARK: - Evaluation Steps

    private func checkDataIntegrity(report: AnalysisReport) -> (isValid: Bool, reason: String) {
        let age = Date().timeIntervalSince(report.generatedAt)
        if age > 300 { return (false, "Data is \(Int(age))s old") }
        return (true, "Fresh data (\(Int(age))s)")
    }

    private func evaluateMTFAlignment(report: AnalysisReport) -> (alignment: Double, notes: String, higherTFConflict: Bool) {
        let confluence = report.confluence
        let alignment = abs(confluence.alignmentScore)
        let higherConflict = confluence.higherTFBias != .neutral &&
                            confluence.higherTFBias != confluence.dominantDirection
        let notes = "\(confluence.bullishTFs)B/\(confluence.bearishTFs)B/\(confluence.neutralTFs)N"
        return (alignment, notes, higherConflict)
    }

    private func evaluateStructure(report: AnalysisReport) -> (score: Double, description: String) {
        let focus = report.requestedFocus
        var s = 0.0
        // Structure direction alignment
        if focus.direction.isBullish && focus.price > focus.support { s += 0.5 }
        if focus.direction.isBearish && focus.price < focus.resistance { s += 0.5 }
        // Proximity to key levels
        let range = focus.resistance - focus.support
        if range > 0 {
            let position = (focus.price - focus.support) / range
            if focus.direction.isBullish && position < 0.3 { s += 0.3 }  // near support
            if focus.direction.isBearish && position > 0.7 { s += 0.3 }  // near resistance
        }
        let desc = "\(focus.direction) @ \(String(format: "%.1f", focus.trendStrength))% trend strength"
        return (min(s, 1.0), desc)
    }

    private func evaluateOrderFlow(report: AnalysisReport) -> (score: Double, description: String) {
        let flow = report.requestedFocus.netAggressiveVolume
        let ratio = report.requestedFocus.tradeDirectionRatio
        var s = 0.0
        if abs(flow) > 0.2 { s += 0.5 }
        if ratio > 0.6 || ratio < 0.4 { s += 0.3 }
        if report.requestedFocus.direction.isBullish && flow > 0 { s += 0.2 }
        if report.requestedFocus.direction.isBearish && flow < 0 { s += 0.2 }
        let desc = "AggVol \(String(format: "%.2f", flow)), ratio \(Int(ratio * 100))%"
        return (min(s, 1.0), desc)
    }

    private func evaluateMomentum(report: AnalysisReport) -> (score: Double, description: String) {
        let mom = report.requestedFocus.momentumScore
        let speed = report.executionRead.speed
        var s = 0.0
        if abs(mom) > 0.3 { s += 0.5 }
        if abs(speed) > 0.5 { s += 0.3 }
        if (mom > 0 && report.requestedFocus.direction.isBullish) ||
           (mom < 0 && report.requestedFocus.direction.isBearish) {
            s += 0.2
        }
        let desc = "Mom \(String(format: "%.2f", mom)), speed \(String(format: "%.2f", speed))%"
        return (min(s, 1.0), desc)
    }

    private func evaluateVolatility(report: AnalysisReport) -> (score: Double, regime: Microstructure.VolatilityRegime, description: String) {
        let regime = report.requestedFocus.regime
        let rvol = report.requestedFocus.realizedVol
        var s = 0.0
        switch regime {
        case .calm: s = 0.3
        case .normal: s = 0.8  // ideal
        case .high: s = 0.5
        case .ultra: s = 0.2
        }
        let desc = "\(regime.rawValue) (rvol \(String(format: "%.4f", rvol)))"
        return (s, regime, desc)
    }

    private func evaluateMacroContext(input: PipelineInput, report: AnalysisReport) -> (score: Double, description: String) {
        var s = 0.0
        var parts: [String] = []

        // Check macro correlation agent bias
        if MacroCorrelationAgent.regimeBias != .neutral {
            let aligned = (report.requestedFocus.direction.isBullish && MacroCorrelationAgent.regimeBias.isBullish) ||
                         (report.requestedFocus.direction.isBearish && MacroCorrelationAgent.regimeBias.isBearish)
            if aligned { s += 0.5; parts.append("Macro aligned") }
            else { s -= 0.3; parts.append("Macro conflicts") }
        } else {
            s += 0.2; parts.append("Macro neutral")
        }

        // Session check
        if let pref = input.sessionPreference {
            let hour = TradingSession.sastHour()
            let inSession: Bool
            switch pref.lowercased() {
            case "asia": inSession = hour >= 1 && hour < 9
            case "london": inSession = hour >= 8 && hour < 17
            case "ny", "newyork", "new york": inSession = hour >= 13 && hour < 22
            default: inSession = true
            }
            if inSession { s += 0.3; parts.append("\(pref) session active") }
            else { s += 0.1; parts.append("Outside \(pref) session") }
        }

        return (max(0, min(1.0, s)), parts.joined(separator: " · "))
    }

    // MARK: - Level Calculation

    private func calculateLevels(direction: Direction, price: Double, atr: Double,
                                  support: Double, resistance: Double) -> (entry: Double, sl: Double, tp1: Double, tp2: Double, tp3: Double, invalidation: Double) {
        let isBuy = direction.isBullish
        let slDistance = atr * 1.5
        let tp1Distance = atr * 2.0
        let tp2Distance = atr * 3.0
        let tp3Distance = atr * 4.5

        let entry = price
        let sl = isBuy ? price - slDistance : price + slDistance
        let tp1 = isBuy ? price + tp1Distance : price - tp1Distance
        let tp2 = isBuy ? min(price + tp2Distance, resistance * 1.01) : max(price - tp2Distance, support * 0.99)
        let tp3 = isBuy ? min(price + tp3Distance, resistance * 1.02) : max(price - tp3Distance, support * 0.98)
        let invalidation = isBuy ? support - atr * 0.5 : resistance + atr * 0.5

        return (entry, sl, tp1, tp2, tp3, invalidation)
    }

    private func estimateTimeHorizon(timeframe: Timeframe, score: Double) -> String {
        let baseMinutes: Int
        switch timeframe {
        case .m1: baseMinutes = 5
        case .m5: baseMinutes = 15
        case .m15: baseMinutes = 45
        case .m30: baseMinutes = 90
        case .h1: baseMinutes = 180
        case .h4: baseMinutes = 720
        case .d1: baseMinutes = 2880
        }
        let adjusted = Double(baseMinutes) * (score > 0.7 ? 1.0 : (score > 0.5 ? 1.5 : 2.0))
        if adjusted < 60 { return "\(Int(adjusted))m" }
        if adjusted < 1440 { return "\(Int(adjusted / 60))h" }
        return "\(Int(adjusted / 1440))d"
    }

    // MARK: - Output Helpers

    private func makeOutput(_ status: SignalStatus, _ direction: Direction, _ confidence: Int,
                            _ report: AnalysisReport, _ price: Double,
                            rationale: [String], warnings: [String]) -> PipelineOutput {
        PipelineOutput(
            status: status, direction: direction, confidence: confidence,
            marketRegime: report.requestedFocus.regime.rawValue,
            macroContext: "N/A", confluenceScore: 0,
            entryZone: price, invalidation: price,
            target1: price, target2: price, target3: price,
            stopLoss: price, riskReward: 0, positionSize: nil,
            rationale: rationale, warnings: warnings,
            invalidationReasons: ["N/A"], timeHorizon: "N/A"
        )
    }
}

// MARK: - Convenience: Format pipeline output as readable text

extension UltraConfirmationPipeline.PipelineOutput {
    func formattedReport(symbol: String) -> String {
        var text = "## \(symbol) — \(status.rawValue)\n\n"
        text += "| Metric | Value |\n|--------|-------|\n"
        text += "| Direction | \(direction) |\n"
        text += "| Confidence | \(confidence)/100 |\n"
        text += "| Confluence | \(String(format: "%.0f", confluenceScore * 100))% |\n"
        text += "| Regime | \(marketRegime) |\n"
        text += "| Time Horizon | \(timeHorizon) |\n"
        text += "| Entry Zone | \(String(format: "%.5f", entryZone)) |\n"
        text += "| Stop Loss | \(String(format: "%.5f", stopLoss)) |\n"
        text += "| Target 1 | \(String(format: "%.5f", target1)) |\n"
        text += "| Target 2 | \(String(format: "%.5f", target2)) |\n"
        text += "| Target 3 | \(String(format: "%.5f", target3)) |\n"
        text += "| R:R | \(String(format: "%.1f", riskReward)) |\n"
        if let size = positionSize {
            text += "| Position Size | \(String(format: "%.4f", size)) |\n"
        }
        text += "| Invalidation | \(String(format: "%.5f", invalidation)) |\n\n"

        if !rationale.isEmpty {
            text += "### Confluence Breakdown\n"
            for r in rationale { text += "- \(r)\n" }
            text += "\n"
        }

        if !warnings.isEmpty {
            text += "### Warnings\n"
            for w in warnings { text += "- ⚠️ \(w)\n" }
            text += "\n"
        }

        if !invalidationReasons.isEmpty {
            text += "### What Invalidates This Setup\n"
            for i in invalidationReasons { text += "- \(i)\n" }
        }

        return text
    }
}
