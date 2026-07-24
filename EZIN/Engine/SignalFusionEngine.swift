import Foundation

/// SignalFusionEngine — unified multi-engine signal aggregator for EZIN.
///
/// Takes inputs from ALL available engines (APEX, quant, neural, systematic,
/// pattern recognition, regime, etc.), applies weighted voting with dynamic
/// weights based on recent performance, and produces a single actionable verdict.
///
/// Outputs are advisory — no order routing.
enum SignalFusionEngine {

    // MARK: - Data Structures

    /// Input from one analysis engine.
    struct EngineInput {
        let name: String
        let direction: Direction
        let confidence: Double       // 0...1
        let weight: Double           // current dynamic weight (0...2)
        let rationale: String
    }

    /// The fused output signal.
    struct FusedSignal {
        let direction: Direction
        let confidence: Double       // 0...100
        let score: Double            // -1...1 weighted blend
        let bullWeight: Double       // total bullish weight
        let bearWeight: Double       // total bearish weight
        let neutralWeight: Double
        let totalEngines: Int
        let agreementPct: Double     // % of non-neutral engines agreeing
        let engineContributions: [EngineContribution]
        let regimeContext: String
        let warnings: [String]
    }

    struct EngineContribution: Identifiable {
        let id = UUID()
        let name: String
        let score: Double            // signed contribution to final score
        let weight: Double
        let direction: Direction
        let rationale: String
    }

    /// Dynamic weight tracker for each engine.
    final class WeightTracker: ObservableObject {
        static let shared = WeightTracker()

        @Published var weights: [String: Double] = [:]
        private var performance: [String: [Bool]] = [:]  // win/loss history
        private let decayFactor = 0.95
        private let maxHistory = 50

        private init() {
            // Initialize default weights
            let engines = [
                "Systematic", "Trend", "Momentum", "MeanReversion", "Volume",
                "Divergence", "Volatility", "Structure", "Ichimoku", "Breakout",
                "Patterns", "Profile", "TrendQuality", "Liquidity", "RegimeSwitch",
                "TapeSpeed", "Neural", "Harmonic", "Elliott", "Bayesian", "Fuzzy"
            ]
            for engine in engines {
                weights[engine] = 1.0
            }
        }

        func recordOutcome(engineName: String, wasCorrect: Bool) {
            var history = performance[engineName] ?? []
            history.append(wasCorrect)
            if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
            performance[engineName] = history

            // Update weight based on recent accuracy
            guard history.count >= 5 else { return }
            let recentHistory = Array(history.suffix(10))
            let accuracy = Double(recentHistory.filter { $0 }.count) / Double(recentHistory.count)

            // Weight = base * accuracy * 2 (so 0.5 accuracy = 1.0 weight)
            let newWeight = max(0.1, min(2.0, accuracy * 2.0))
            weights[engineName] = newWeight * decayFactor + (weights[engineName] ?? 1.0) * (1 - decayFactor)
        }

        func resetAll() {
            for key in weights.keys { weights[key] = 1.0 }
            performance.removeAll()
        }
    }

    // MARK: - Fusion Engine

    /// Fuse multiple engine inputs into a single actionable signal.
    /// - Parameters:
    ///   - inputs: Array of EngineInputs from all available engines
    ///   - useDynamicWeights: Whether to apply learned dynamic weights
    /// - Returns: FusedSignal with all contributions and context
    static func fuse(inputs: [EngineInput], useDynamicWeights: Bool = true) -> FusedSignal {
        guard !inputs.isEmpty else {
            return FusedSignal(
                direction: .neutral, confidence: 0, score: 0,
                bullWeight: 0, bearWeight: 0, neutralWeight: 0,
                totalEngines: 0, agreementPct: 0,
                engineContributions: [], regimeContext: "No engine inputs available",
                warnings: ["No analysis engines produced output"]
            )
        }

        let tracker = WeightTracker.shared

        // Apply dynamic weights
        var weightedInputs: [(input: EngineInput, effectiveWeight: Double)] = []
        for input in inputs {
            let dynamicWeight = useDynamicWeights ? (tracker.weights[input.name] ?? 1.0) : 1.0
            let effectiveWeight = input.weight * dynamicWeight * input.confidence
            weightedInputs.append((input, effectiveWeight))
        }

        // Calculate weighted scores
        var bullWeight = 0.0
        var bearWeight = 0.0
        var neutralWeight = 0.0
        var totalWeight = 0.0

        for (input, effectiveWeight) in weightedInputs {
            totalWeight += effectiveWeight
            switch input.direction {
            case .bullish, .strongBullish:
                let signed = input.direction == .strongBullish ? effectiveWeight * 1.3 : effectiveWeight
                bullWeight += signed
            case .bearish, .strongBearish:
                let signed = input.direction == .strongBearish ? effectiveWeight * 1.3 : effectiveWeight
                bearWeight += signed
            case .neutral:
                neutralWeight += effectiveWeight * 0.3
            }
        }

        // Normalize to -1...+1
        let totalForScore = max(bullWeight + bearWeight + neutralWeight, 0.000001)
        let score = (bullWeight - bearWeight) / totalForScore

        // Determine direction
        let direction: Direction
        switch score {
        case let s where s >= 0.6: direction = .strongBullish
        case let s where s >= 0.15: direction = .bullish
        case let s where s <= -0.6: direction = .strongBearish
        case let s where s <= -0.15: direction = .bearish
        default: direction = .neutral
        }

        // Confidence: magnitude of score
        let confidence = min(abs(score) * 100, 100)

        // Agreement percentage among non-neutral engines
        let nonNeutral = inputs.filter { $0.direction != .neutral }
        let agreeing = nonNeutral.filter { ($0.direction.isBullish && direction.isBullish) || ($0.direction.isBearish && direction.isBearish) }
        let agreementPct = nonNeutral.isEmpty ? 0 : Double(agreeing.count) / Double(nonNeutral.count) * 100

        // Build contributions
        let contributions = weightedInputs.map { (input, effectiveWeight) -> EngineContribution in
            let signedScore: Double
            switch input.direction {
            case .bullish: signedScore = effectiveWeight / max(totalForScore, 0.000001)
            case .strongBullish: signedScore = effectiveWeight * 1.3 / max(totalForScore, 0.000001)
            case .bearish: signedScore = -effectiveWeight / max(totalForScore, 0.000001)
            case .strongBearish: signedScore = -effectiveWeight * 1.3 / max(totalForScore, 0.000001)
            case .neutral: signedScore = 0
            }
            return EngineContribution(
                name: input.name,
                score: signedScore,
                weight: input.weight,
                direction: input.direction,
                rationale: input.rationale
            )
        }.sorted { abs($0.score) > abs($1.score) }

        // Determine regime context from the blend
        let spread = bullWeight + bearWeight
        let regimeContext: String
        if neutralWeight > spread * 0.5 {
            regimeContext = "High uncertainty / mixed signals — reduce position size or wait for clearer alignment"
        } else if bullWeight > bearWeight * 2 {
            regimeContext = "Strong bullish consensus — look for pullback entries with tight invalidation"
        } else if bearWeight > bullWeight * 2 {
            regimeContext = "Strong bearish consensus — avoid catching falling knives"
        } else if spread > 0 {
            regimeContext = "Moderate \(direction.isBullish ? "bullish" : "bearish") bias with some dissent — use structure confirmation"
        } else {
            regimeContext = "Engines are evenly split — wait for higher timeframe confirmation"
        }

        // Warnings
        var warnings: [String] = []
        if neutralWeight > spread * 0.7 {
            warnings.append("Most engines are neutral — no clear edge")
        }
        if inputs.count < 4 {
            warnings.append("Only \(inputs.count) engines contributed — less diverse signal")
        }
        if abs(score) < 0.2 {
            warnings.append("Signal strength is weak — consider waiting for stronger alignment")
        }

        return FusedSignal(
            direction: direction,
            confidence: confidence,
            score: score,
            bullWeight: bullWeight,
            bearWeight: bearWeight,
            neutralWeight: neutralWeight,
            totalEngines: inputs.count,
            agreementPct: agreementPct,
            engineContributions: contributions,
            regimeContext: regimeContext,
            warnings: warnings
        )
    }

    // MARK: - Report Generation

    /// Generate a formatted fusion report.
    static func fusionReport(
        symbol: String,
        inputs: [EngineInput],
        useDynamicWeights: Bool = true
    ) -> String {
        let fused = fuse(inputs: inputs, useDynamicWeights: useDynamicWeights)

        guard !inputs.isEmpty else {
            return "## Signal Fusion — \(DerivSymbols.display(symbol))\n\nNo engine inputs available. Enable analysis engines (chat agents, APEX, quant backend) and try again."
        }

        var report = "## Signal Fusion — \(DerivSymbols.display(symbol))\n\n"

        // Verdict
        let dirIcon: String
        switch fused.direction {
        case .strongBullish: dirIcon = "🟢🟢"
        case .bullish: dirIcon = "🟢"
        case .neutral: dirIcon = "⚪"
        case .bearish: dirIcon = "🔴"
        case .strongBearish: dirIcon = "🔴🔴"
        }
        report += "### Verdict: \(dirIcon) \(dirLabel(fused.direction)) · Confidence: \(fmt(fused.confidence))% · Score: \(fmt(fused.score))\n\n"

        // Summary
        report += "| Metric | Value |\n|---|---|\n"
        report += "| Engines Contributing | \(fused.totalEngines) |\n"
        report += "| Bullish Weight | \(fmt(fused.bullWeight)) |\n"
        report += "| Bearish Weight | \(fmt(fused.bearWeight)) |\n"
        report += "| Neutral Weight | \(fmt(fused.neutralWeight)) |\n"
        report += "| Agreement | \(fmt(fused.agreementPct))% of non-neutral engines |\n\n"

        report += "**Context:** \(fused.regimeContext)\n\n"

        // Warnings
        if !fused.warnings.isEmpty {
            report += "⚠️ Warnings:\n"
            for warning in fused.warnings {
                report += "- \(warning)\n"
            }
            report += "\n"
        }

        // Engine contributions
        report += "### Engine Contributions\n\n"
        report += "| Engine | Score | Direction | Weight | Rationale |\n|---|---|---|---|---|\n"
        for contrib in fused.engineContributions.prefix(10) {
            let dirArrow = contrib.direction.isBullish ? "🟢" : (contrib.direction.isBearish ? "🔴" : "⚪")
            report += "| \(contrib.name) | \(fmt(contrib.score)) | \(dirArrow) \(dirLabel(contrib.direction)) | \(fmt(contrib.weight)) | \(contrib.rationale.prefix(60)) |\n"
        }

        // Dynamic weights info
        if useDynamicWeights {
            let tracker = WeightTracker.shared
            report += "\n### Dynamic Weights\n\n"
            report += "| Engine | Current Weight |\n|---|---|\n"
            for (name, weight) in tracker.weights.sorted(by: { $0.value > $1.value }).prefix(8) {
                let bar = String(repeating: "█", count: Int(weight * 10))
                report += "| \(name) | \(bar) \(fmt(weight)) |\n"
            }
        }

        report += "\n---\n*Signal fusion aggregates multiple on-device engines into a single confluence score. Not a trade recommendation.*"

        return report
    }

    // MARK: - EZIN Integration

    /// Build EngineInputs from the full EZIN analysis stack.
    static func buildInputs(
        symbol: String,
        timeframe: Timeframe,
        app: AppState
    ) -> [EngineInput] {
        var inputs: [EngineInput] = []

        guard let md = app.deriv.priceCache[symbol]?.toMarketData(symbol: symbol, timeframe: timeframe),
              md.closes.count >= 30 else {
            return inputs
        }

        let ind = app.engine.analyzer.analyze(md)

        // 1. Systematic engine
        let systematic = BackendQuantEngine.systematic(md)
        inputs.append(EngineInput(
            name: "Systematic", direction: systematic.direction,
            confidence: Double(systematic.confidence) / 100,
            weight: 1.0,
            rationale: "trend \(fmt(systematic.trend)) · momentum \(fmt(systematic.momentum))"
        ))

        // 2. Agent council (Trend, Momentum, etc.)
        for agent in app.engine.agents where agent.isActive {
            let vote = agent.analyze(md, ind)
            inputs.append(EngineInput(
                name: agent.name, direction: vote.direction,
                confidence: vote.confidence, weight: vote.weight,
                rationale: vote.rationale
            ))
        }

        // 3. APEX engines
        // Pattern engine
        let patterns = ApexBackend.candlePatterns(md)
        if !patterns.isEmpty {
            let bull = patterns.filter { $0.bullish }.reduce(0) { $0 + $1.strength }
            let bear = patterns.filter { !$0.bullish }.reduce(0) { $0 + $1.strength }
            let score = (bull - bear) / max(bull + bear, 0.01)
            let dir: Direction = score > 0.15 ? .bullish : (score < -0.15 ? .bearish : .neutral)
            inputs.append(EngineInput(
                name: "Patterns", direction: dir, confidence: min(abs(score) * 0.5 + 0.2, 0.8), weight: 0.95,
                rationale: "\(patterns.count) patterns · score \(fmt(score))"
            ))
        }

        // Market profile
        if let profile = ApexBackend.marketProfile(md) {
            let price = md.currentPrice > 0 ? md.currentPrice : (md.closes.last ?? 0)
            let dir: Direction = price > profile.valueAreaHigh ? .bullish : (price < profile.valueAreaLow ? .bearish : .neutral)
            inputs.append(EngineInput(
                name: "Profile", direction: dir, confidence: 0.55, weight: 0.85,
                rationale: profile.positionLabel
            ))
        }

        // Liquidity
        let liq = ApexBackend.liquidityMap(md)
        if liq.sweptBelow {
            inputs.append(EngineInput(name: "Liquidity", direction: .bullish, confidence: 0.7, weight: 1.0, rationale: "sell-side sweep"))
        } else if liq.sweptAbove {
            inputs.append(EngineInput(name: "Liquidity", direction: .bearish, confidence: 0.7, weight: 1.0, rationale: "buy-side sweep"))
        }

        // Regime
        if let regime = ApexBackend.regimeSwitch(md.closes) {
            let dir: Direction = regime.bull > regime.bear + 0.2 ? .bullish : (regime.bear > regime.bull + 0.2 ? .bearish : .neutral)
            inputs.append(EngineInput(
                name: "RegimeSwitch", direction: dir, confidence: regime.persistence, weight: 0.9,
                rationale: "\(regime.dominant) · \(fmt(regime.persistence)) sticky"
            ))
        }

        // Entropy / trend quality
        if let entropy = ApexBackend.entropyAnalysis(md.closes) {
            let trendDir = (md.closes.last ?? 0) > (md.closes.count > 21 ? md.closes[md.closes.count - 21] : md.closes.first ?? 0) ? Direction.bullish : Direction.bearish
            let conf = min(entropy.efficiencyRatio * 0.8, 0.8)
            inputs.append(EngineInput(
                name: "TrendQuality", direction: trendDir, confidence: conf, weight: 0.8,
                rationale: "ER \(fmt(entropy.efficiencyRatio)) · \(entropy.trendQuality)"
            ))
        }

        // Tape speed
        if let speed = ApexBackend.tickSpeed(md.closes, perSeconds: 60) {
            let dir: Direction = speed.velocity > 2 ? .bullish : (speed.velocity < -2 ? .bearish : .neutral)
            inputs.append(EngineInput(
                name: "TapeSpeed", direction: dir,
                confidence: min(abs(speed.velocity) / 15, 0.7), weight: 0.7,
                rationale: speed.reading
            ))
        }

        // 4. Neural engine
        let neural = AdvancedBackend.neuralSignal(md)
        if neural.samples > 0 {
            let dir: Direction = neural.probabilityUp > 0.56 ? .bullish : (neural.probabilityUp < 0.44 ? .bearish : .neutral)
            inputs.append(EngineInput(
                name: "Neural", direction: dir,
                confidence: abs(neural.probabilityUp - 0.5) * 2 * neural.accuracy,
                weight: 0.6,
                rationale: "P(up) \(fmt(neural.probabilityUp)) · acc \(fmt(neural.accuracy))"
            ))
        }

        // 5. Bayesian
        let bayesianDir = bayesianDirection(md: md)
        let bayesianConf = bayesianConfidence(md: md)
        if bayesianConf > 0.1 {
            inputs.append(EngineInput(
                name: "Bayesian", direction: bayesianDir, confidence: bayesianConf, weight: 0.7,
                rationale: "posterior P(up) \(fmt(bayesianConf))"
            ))
        }

        return inputs
    }

    // MARK: - Private Helpers

    private static func bayesianDirection(md: MarketData) -> Direction {
        let systematic = BackendQuantEngine.systematic(md)
        let neural = AdvancedBackend.neuralSignal(md)
        let closes = md.closes
        let prior = closes.last! > (closes.dropLast(20).last ?? closes.last!) ? 0.55 : 0.45
        var pUp = prior
        pUp = AdvancedBackend.update(prior: pUp, likelihoodPositive: 0.5 + Double(systematic.direction.rawValue) * 0.1, evidence: Double(systematic.confidence) / 100)
        pUp = AdvancedBackend.update(prior: pUp, likelihoodPositive: neural.probabilityUp, evidence: abs(neural.probabilityUp - 0.5) * 2)
        if pUp > 0.56 { return .bullish }
        if pUp < 0.44 { return .bearish }
        return .neutral
    }

    private static func bayesianConfidence(md: MarketData) -> Double {
        let systematic = BackendQuantEngine.systematic(md)
        let neural = AdvancedBackend.neuralSignal(md)
        var pUp = 0.5
        pUp = AdvancedBackend.update(prior: pUp, likelihoodPositive: 0.5 + Double(systematic.direction.rawValue) * 0.1, evidence: Double(systematic.confidence) / 100)
        pUp = AdvancedBackend.update(prior: pUp, likelihoodPositive: neural.probabilityUp, evidence: abs(neural.probabilityUp - 0.5) * 2)
        return abs(pUp - 0.5) * 2
    }

    private static func dirLabel(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "Strong Bullish"
        case .bullish: return "Bullish"
        case .neutral: return "Neutral"
        case .bearish: return "Bearish"
        case .strongBearish: return "Strong Bearish"
        }
    }

    private static func fmt(_ x: Double, _ places: Int = 3) -> String {
        String(format: "%%.\(places)f", x)
    }
}
