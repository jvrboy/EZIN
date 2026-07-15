import Foundation

/// EZIN Brain — a self-learning system that grows smarter with every signal.
///
/// The Brain:
///   1. Remembers every signal's market context (indicators, regime, time, symbol)
///   2. Learns from outcomes (TP hit, SL hit, expired)
///   3. Builds pattern memory — which conditions predict success
///   4. Adjusts future signal confidence based on learned patterns
///   5. Provides evolving recommendations
///
/// This is NOT a deep neural network (iOS constraints) — it's a sophisticated
/// pattern-matching and statistical learning system that mimics how institutional
/// quants build alpha: by finding repeatable edge in market microstructure.
@MainActor
final class BrainEngine: ObservableObject {
    static let shared = BrainEngine()

    @Published var patternMemory: PatternMemory = PatternMemory()
    @Published var learningStats: LearningStats = LearningStats()
    @Published var isLearning = false

    private let memoryFile = "brain_pattern_memory.json"
    private let statsFile = "brain_learning_stats.json"
    private var learningQueue: [SignalExperience] = []
    private let queueLimit = 100

    private init() { load() }

    // MARK: - Experience Recording

    /// Record a signal experience for learning. Called when a signal is generated.
    func recordExperience(signal: TradingSignal, context: MarketContext) {
        let exp = SignalExperience(
            id: signal.id,
            symbol: signal.symbol,
            timeframe: signal.timeframe.rawValue,
            direction: signal.isBuy ? "buy" : "sell",
            confidence: signal.confidence,
            regime: context.regime,
            volatilityPercent: context.volatilityPercent,
            trendStrength: context.trendStrength,
            momentumScore: context.momentumScore,
            volumeBias: context.volumeBias,
            orderFlowBias: context.orderFlowBias,
            rsi: context.rsi,
            macdHistogram: context.macdHistogram,
            atrPercent: context.atrPercent,
            hourOfDay: context.hourOfDay,
            outcome: nil,
            recordedAt: Date()
        )
        learningQueue.append(exp)
        if learningQueue.count > queueLimit {
            learningQueue.removeFirst(learningQueue.count - queueLimit)
        }
        save()
    }

    /// Record the outcome of a signal (called when TP/SL is hit or signal expires).
    func recordOutcome(signalID: UUID, outcome: SignalOutcome) {
        // Update in queue
        if let idx = learningQueue.firstIndex(where: { $0.id == signalID }) {
            learningQueue[idx].outcome = outcome
            learn(from: learningQueue[idx])
        }
        learningStats.totalLearned += 1
        if case .hitTakeProfit = outcome { learningStats.successfulPredictions += 1 }
        save()
    }

    // MARK: - Learning

    private func learn(from experience: SignalExperience) {
        guard let outcome = experience.outcome else { return }
        isLearning = true
        defer { isLearning = false }

        let wasWin = outcome == .hitTakeProfit

        // Learn symbol patterns
        patternMemory.symbolPatterns[experience.symbol, default: SymbolPattern()]
            .addResult(win: wasWin)

        // Learn timeframe patterns
        patternMemory.timeframePatterns[experience.timeframe, default: TimeframePattern()]
            .addResult(win: wasWin)

        // Learn regime patterns
        patternMemory.regimePatterns[experience.regime, default: RegimePattern()]
            .addResult(win: wasWin)

        // Learn hour-of-day patterns
        let hourKey = String(experience.hourOfDay)
        patternMemory.hourPatterns[hourKey, default: HourPattern()]
            .addResult(win: wasWin)

        // Learn confidence calibration (does our confidence match reality?)
        let confBucket = Int(experience.confidence / 10) * 10  // 0, 10, 20, ..., 100
        patternMemory.confidenceCalibration[confBucket, default: ConfidenceCalibration()]
            .addResult(win: wasWin)

        // Learn multi-factor patterns (the most powerful)
        let factorKey = FactorKey(
            regime: experience.regime,
            trendStrength: categorizeTrendStrength(experience.trendStrength),
            volumeBias: experience.volumeBias,
            direction: experience.direction
        )
        patternMemory.factorPatterns[factorKey, default: FactorPattern()]
            .addResult(win: wasWin)

        // Update overall calibration
        learningStats.calibrationError = calculateCalibrationError()
    }

    // MARK: - Prediction / Confidence Adjustment

    /// Adjust a signal's confidence based on what the Brain has learned.
    func adjustConfidence(symbol: String, timeframe: Timeframe, originalConfidence: Double,
                          context: MarketContext) -> (adjusted: Double, reason: String) {
        var multiplier = 1.0
        var reasons: [String] = []

        // Symbol factor
        if let symPattern = patternMemory.symbolPatterns[symbol], symPattern.total >= 3 {
            let symEdge = symPattern.winRate - 0.5  // positive = edge
            multiplier += symEdge * 0.2
            reasons.append("\(symbol) WR \(Int(symPattern.winRate * 100))%")
        }

        // Timeframe factor
        let tfStr = timeframe.rawValue
        if let tfPattern = patternMemory.timeframePatterns[tfStr], tfPattern.total >= 3 {
            let tfEdge = tfPattern.winRate - 0.5
            multiplier += tfEdge * 0.15
            reasons.append("\(tfStr) WR \(Int(tfPattern.winRate * 100))%")
        }

        // Regime factor
        if let regPattern = patternMemory.regimePatterns[context.regime], regPattern.total >= 3 {
            let regEdge = regPattern.winRate - 0.5
            multiplier += regEdge * 0.2
            reasons.append("\(context.regime) WR \(Int(regPattern.winRate * 100))%")
        }

        // Hour factor
        let hourKey = String(context.hourOfDay)
        if let hourPattern = patternMemory.hourPatterns[hourKey], hourPattern.total >= 3 {
            let hourEdge = hourPattern.winRate - 0.5
            multiplier += hourEdge * 0.1
            reasons.append("H\(context.hourOfDay) WR \(Int(hourPattern.winRate * 100))%")
        }

        // Confidence calibration
        let confBucket = Int(originalConfidence / 10) * 10
        if let cal = patternMemory.confidenceCalibration[confBucket], cal.total >= 5 {
            let actualWR = cal.winRate
            let expectedWR = originalConfidence / 100.0
            let calibration = actualWR - expectedWR
            if calibration < -0.15 {
                multiplier -= 0.1  // our confidence is over-optimistic
                reasons.append("calibrated down")
            } else if calibration > 0.15 {
                multiplier += 0.1  // we're under-confident
                reasons.append("calibrated up")
            }
        }

        // Factor pattern (most powerful)
        let factorKey = FactorKey(
            regime: context.regime,
            trendStrength: categorizeTrendStrength(context.trendStrength),
            volumeBias: context.volumeBias,
            direction: context.direction
        )
        if let factorPattern = patternMemory.factorPatterns[factorKey], factorPattern.total >= 5 {
            let factorEdge = factorPattern.winRate - 0.5
            multiplier += factorEdge * 0.25
            reasons.append("factor WR \(Int(factorPattern.winRate * 100))%")
        }

        let adjusted = max(5, min(98, originalConfidence * multiplier))
        let reason = reasons.isEmpty ? "insufficient data" : reasons.joined(separator: " · ")
        return (adjusted, reason)
    }

    // MARK: - Insights

    func getInsights() -> [String] {
        var insights: [String] = []

        guard learningStats.totalLearned >= 5 else {
            return ["Brain is learning... \(learningStats.totalLearned) signals processed so far. Need at least 5 for insights."]
        }

        // Best symbol
        if let best = patternMemory.symbolPatterns.max(by: { $0.value.winRate < $1.value.winRate }),
           best.value.total >= 3 {
            insights.append("Best symbol: \(DerivSymbols.display(best.key)) (\(Int(best.value.winRate * 100))% WR, \(best.value.total) samples)")
        }

        // Best timeframe
        if let best = patternMemory.timeframePatterns.max(by: { $0.value.winRate < $1.value.winRate }),
           best.value.total >= 3 {
            insights.append("Best timeframe: \(best.key) (\(Int(best.value.winRate * 100))% WR)")
        }

        // Best regime
        if let best = patternMemory.regimePatterns.max(by: { $0.value.winRate < $1.value.winRate }),
           best.value.total >= 3 {
            insights.append("Best regime: \(best.key) (\(Int(best.value.winRate * 100))% WR)")
        }

        // Best hour
        if let best = patternMemory.hourPatterns.max(by: { $0.value.winRate < $1.value.winRate }),
           best.value.total >= 3, let hour = Int(best.key) {
            insights.append("Best hour: \(hour):00 (\(Int(best.value.winRate * 100))% WR)")
        }

        // Overall accuracy
        let accuracy = learningStats.totalLearned > 0 ? Double(learningStats.successfulPredictions) / Double(learningStats.totalLearned) : 0
        insights.append("Overall prediction accuracy: \(Int(accuracy * 100))% (\(learningStats.totalLearned) signals)")

        // Calibration
        if abs(learningStats.calibrationError) > 0.1 {
            let direction = learningStats.calibrationError > 0 ? "under-confident" : "over-confident"
            insights.append("Calibration: \(direction) by \(String(format: "%.0f", abs(learningStats.calibrationError) * 100))%")
        }

        return insights
    }

    func getBrainReport() -> String {
        let insights = getInsights()
        var report = "# EZIN Brain Report\n\n"
        report += "**Status**: \(isLearning ? "Learning..." : "Active")\n"
        report += "**Signals Learned**: \(learningStats.totalLearned)\n"
        report += "**Success Rate**: \(Int((learningStats.totalLearned > 0 ? Double(learningStats.successfulPredictions) / Double(learningStats.totalLearned) : 0) * 100))%\n"
        report += "**Calibration Error**: \(String(format: "%.1f", learningStats.calibrationError * 100))%\n\n"
        report += "## Insights\n\n"
        for insight in insights {
            report += "- \(insight)\n"
        }
        report += "\n## Pattern Memory\n\n"
        report += "- Symbols tracked: \(patternMemory.symbolPatterns.count)\n"
        report += "- Timeframe patterns: \(patternMemory.timeframePatterns.count)\n"
        report += "- Regime patterns: \(patternMemory.regimePatterns.count)\n"
        report += "- Hour patterns: \(patternMemory.hourPatterns.count)\n"
        report += "- Factor patterns: \(patternMemory.factorPatterns.count)\n"
        return report
    }

    // MARK: - Private Helpers

    private func categorizeTrendStrength(_ strength: Double) -> String {
        switch strength {
        case let s where s > 70: return "strong"
        case let s where s > 40: return "moderate"
        default: return "weak"
        }
    }

    private func calculateCalibrationError() -> Double {
        var totalError = 0.0
        var count = 0
        for (confBucket, cal) in patternMemory.confidenceCalibration where cal.total >= 5 {
            let expectedWR = Double(confBucket) / 100.0
            let actualWR = cal.winRate
            totalError += actualWR - expectedWR
            count += 1
        }
        return count > 0 ? totalError / Double(count) : 0
    }

    // MARK: - Persistence

    private func save() {
        FileStore.shared.write(patternMemory, to: memoryFile, in: FileStore.shared.dataDir)
        FileStore.shared.write(learningStats, to: statsFile, in: FileStore.shared.dataDir)
    }

    private func load() {
        patternMemory = FileStore.shared.read(PatternMemory.self, from: memoryFile, in: FileStore.shared.dataDir) ?? PatternMemory()
        learningStats = FileStore.shared.read(LearningStats.self, from: statsFile, in: FileStore.shared.dataDir) ?? LearningStats()
    }

    func reset() {
        patternMemory = PatternMemory()
        learningStats = LearningStats()
        learningQueue.removeAll()
        save()
    }
}

// MARK: - Data Models

struct SignalExperience: Codable {
    let id: UUID
    let symbol: String
    let timeframe: String
    let direction: String
    let confidence: Double
    let regime: String
    let volatilityPercent: Double
    let trendStrength: Double
    let momentumScore: Double
    let volumeBias: String
    let orderFlowBias: String
    let rsi: Double
    let macdHistogram: Double
    let atrPercent: Double
    let hourOfDay: Int
    var outcome: SignalOutcome?
    let recordedAt: Date
}

enum SignalOutcome: String, Codable {
    case hitTakeProfit, hitStopLoss, expired
}

struct MarketContext: Codable {
    let regime: String
    let volatilityPercent: Double
    let trendStrength: Double
    let momentumScore: Double
    let volumeBias: String
    let orderFlowBias: String
    let rsi: Double
    let macdHistogram: Double
    let atrPercent: Double
    let hourOfDay: Int
    let direction: String
}

struct PatternMemory: Codable {
    var symbolPatterns: [String: SymbolPattern] = [:]
    var timeframePatterns: [String: TimeframePattern] = [:]
    var regimePatterns: [String: RegimePattern] = [:]
    var hourPatterns: [String: HourPattern] = [:]
    var confidenceCalibration: [Int: ConfidenceCalibration] = [:]
    var factorPatterns: [FactorKey: FactorPattern] = [:]
}

struct SymbolPattern: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total > 0 ? Double(wins) / Double(total) : 0.5 }
    mutating func addResult(win: Bool) { if win { wins += 1 } else { losses += 1 } }
}

struct TimeframePattern: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total > 0 ? Double(wins) / Double(total) : 0.5 }
    mutating func addResult(win: Bool) { if win { wins += 1 } else { losses += 1 } }
}

struct RegimePattern: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total > 0 ? Double(wins) / Double(total) : 0.5 }
    mutating func addResult(win: Bool) { if win { wins += 1 } else { losses += 1 } }
}

struct HourPattern: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total > 0 ? Double(wins) / Double(total) : 0.5 }
    mutating func addResult(win: Bool) { if win { wins += 1 } else { losses += 1 } }
}

struct ConfidenceCalibration: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total > 0 ? Double(wins) / Double(total) : 0.5 }
    mutating func addResult(win: Bool) { if win { wins += 1 } else { losses += 1 } }
}

struct FactorKey: Codable, Hashable {
    let regime: String
    let trendStrength: String
    let volumeBias: String
    let direction: String
}

struct FactorPattern: Codable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total > 0 ? Double(wins) / Double(total) : 0.5 }
    mutating func addResult(win: Bool) { if win { wins += 1 } else { losses += 1 } }
}

struct LearningStats: Codable {
    var totalLearned: Int = 0
    var successfulPredictions: Int = 0
    var calibrationError: Double = 0
}
