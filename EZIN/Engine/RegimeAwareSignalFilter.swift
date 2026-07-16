import Foundation

/// Regime-aware signal filtering configuration
struct RegimeFilterConfig: Codable {
    /// Enable regime-based signal filtering (default: true)
    var enabled: Bool = true
    /// Minimum confidence boost required when regime matches signal direction (0.0-0.3, default: 0.05)
    var confidenceBoost: Double = 0.05
    /// Confidence penalty when regime contradicts signal direction (0.0-0.5, default: 0.15)
    var contradictionPenalty: Double = 0.15
    /// Minimum regime-structure agreement score to allow signal through (0.0-1.0, default: 0.3)
    var minAgreementScore: Double = 0.3
    /// When true, suppress signals entirely on contradiction; when false, apply penalty only
    var hardSuppression: Bool = false

    /// Lookback for structure detection (in candles)
    var structureLookback: Int = 50

    static let storageKey = "regimeFilterConfig.v1"
}

/// Regime-structure disagreement analysis result
struct RegimeStructureAnalysis {
    let regime: Microstructure.VolatilityRegime
    let structureDirection: Direction
    let agreementScore: Double  // -1.0 to 1.0, positive = bullish agreement
    let disagreementType: DisagreementType
    let shouldSuppress: Bool
    let adjustedConfidence: Double

    enum DisagreementType {
        case agreement           // Regime and structure agree
        case regimeMismatch      // Volatility regime contradicts trend
        case structureWeak      // Structure is weak/ambiguous
        case conflicting         // Bullish regime vs bearish structure or vice versa
        case neutral             // No clear disagreement
    }
}

/// Regime-aware signal filter that suppresses low-quality signals
/// when market regime and technical structure disagree
final class RegimeAwareSignalFilter: ObservableObject {
    static let shared = RegimeAwareSignalFilter()

    @Published var config: RegimeFilterConfig {
        didSet { save() }
    }
    private let d = UserDefaults.standard

    private init() {
        if let data = d.data(forKey: RegimeFilterConfig.storageKey),
           let cfg = try? JSONDecoder().decode(RegimeFilterConfig.self, from: data) {
            config = cfg
        } else {
            config = RegimeFilterConfig()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            d.set(data, forKey: RegimeFilterConfig.storageKey)
        }
    }

    // MARK: - Main Filtering Logic

    /// Analyze a potential signal against regime-structure alignment
    func analyzeSignal(
        signal: TradingSignal,
        candles: [Candle],
        agentVotes: [AgentVote]
    ) -> RegimeStructureAnalysis {
        guard config.enabled else {
            return RegimeStructureAnalysis(
                regime: .normal,
                structureDirection: signal.type.direction,
                agreementScore: 1.0,
                disagreementType: .agreement,
                shouldSuppress: false,
                adjustedConfidence: signal.confidence
            )
        }

        // 1. Detect current volatility regime
        let regime = Microstructure.regime(candles.map { $0.close })

        // 2. Detect structure direction from candles
        let structureDir = detectStructureDirection(candles: candles)

        // 3. Calculate agreement score
        let agreementScore = calculateAgreementScore(
            regime: regime,
            structureDirection: structureDir,
            signalDirection: signal.type.direction
        )

        // 4. Determine disagreement type
        let disagreementType = classifyDisagreement(
            regime: regime,
            structureDirection: structureDir,
            signalDirection: signal.type.direction
        )

        // 5. Adjust confidence based on agreement
        var adjustedConfidence = signal.confidence
        var shouldSuppress = false

        if agreementScore < config.minAgreementScore {
            // Regime-structure disagreement detected
            if disagreementType == .conflicting || config.hardSuppression {
                // Hard suppression for conflicting signals
                shouldSuppress = true
                adjustedConfidence = 0
            } else {
                // Apply penalty
                adjustedConfidence = max(0, signal.confidence - (config.contradictionPenalty * 100))
            }
        } else if agreementScore > 0.5 {
            // Positive agreement - boost confidence slightly
            adjustedConfidence = min(100, signal.confidence + (config.confidenceBoost * 100))
        }

        return RegimeStructureAnalysis(
            regime: regime,
            structureDirection: structureDir,
            agreementScore: agreementScore,
            disagreementType: disagreementType,
            shouldSuppress: shouldSuppress,
            adjustedConfidence: adjustedConfidence
        )
    }

    /// Filter signals - returns nil if signal should be suppressed
    func filterSignal(
        signal: TradingSignal,
        candles: [Candle],
        agentVotes: [AgentVote]
    ) -> TradingSignal? {
        let analysis = analyzeSignal(signal: signal, candles: candles, agentVotes: agentVotes)

        if analysis.shouldSuppress {
            return nil
        }

        // Return signal with adjusted confidence
        var filteredSignal = signal
        filteredSignal.confidence = analysis.adjustedConfidence
        return filteredSignal
    }

    // MARK: - Structure Detection

    /// Detect market structure direction (trend) from price action
    private func detectStructureDirection(candles: [Candle]) -> Direction {
        guard candles.count >= config.structureLookback else {
            return .neutral
        }

        let lookbackCandles = Array(candles.suffix(config.structureLookback))
        let closes = lookbackCandles.map { $0.close }

        // Use multiple methods for robust structure detection
        let hhCount = countHigherHighs(candles: lookbackCandles)
        let hlCount = countHigherLows(candles: lookbackCandles)
        let llCount = countLowerLows(candles: lookbackCandles)
        let lhCount = countLowerHighs(candles: lookbackCandles)

        // Linear regression slope
        let slope = Indicators.linRegSlope(closes, min(closes.count, 20)).last ?? 0

        // Score-based direction
        var bullishScore = 0
        var bearishScore = 0

        // Higher highs and higher lows = uptrend
        if hhCount >= 2 { bullishScore += 1 }
        if hlCount >= 2 { bullishScore += 1 }

        // Lower highs and lower lows = downtrend
        if lhCount >= 2 { bearishScore += 1 }
        if llCount >= 2 { bearishScore += 1 }

        // Slope contribution
        if slope > 0.0001 { bullishScore += 1 }
        if slope < -0.0001 { bearishScore += 1 }

        // Determine direction
        if bullishScore > bearishScore + 1 {
            return .bullish
        } else if bearishScore > bullishScore + 1 {
            return .bearish
        } else if bullishScore > 0 || bearishScore > 0 {
            return .neutral
        }

        // Fallback to slope-only
        if slope > 0.0001 { return .bullish }
        if slope < -0.0001 { return .bearish }
        return .neutral
    }

    private func countHigherHighs(candles: [Candle]) -> Int {
        var count = 0
        let highs = candles.map { $0.high }
        for i in 2..<highs.count {
            if highs[i] > highs[i-1] && highs[i-1] > highs[i-2] {
                count += 1
            }
        }
        return count
    }

    private func countHigherLows(candles: [Candle]) -> Int {
        var count = 0
        let lows = candles.map { $0.low }
        for i in 2..<lows.count {
            if lows[i] > lows[i-1] && lows[i-1] > lows[i-2] {
                count += 1
            }
        }
        return count
    }

    private func countLowerHighs(candles: [Candle]) -> Int {
        var count = 0
        let highs = candles.map { $0.high }
        for i in 2..<highs.count {
            if highs[i] < highs[i-1] && highs[i-1] < highs[i-2] {
                count += 1
            }
        }
        return count
    }

    private func countLowerLows(candles: [Candle]) -> Int {
        var count = 0
        let lows = candles.map { $0.low }
        for i in 2..<lows.count {
            if lows[i] < lows[i-1] && lows[i-1] < lows[i-2] {
                count += 1
            }
        }
        return count
    }

    // MARK: - Agreement Calculation

    /// Calculate how well regime and structure agree with signal direction
    private func calculateAgreementScore(
        regime: Microstructure.VolatilityRegime,
        structureDirection: Direction,
        signalDirection: Direction
    ) -> Double {
        // Regime-to-direction mapping
        // High vol regimes can occur in both bull and bear markets
        // Calm regimes often precede reversals or continuation
        let regimeBias: Double
        switch regime {
        case .calm:
            // Calm markets can breakout in either direction - neutral bias
            regimeBias = 0.0
        case .normal:
            regimeBias = 0.1  // Slight bullish tendency in normal markets
        case .high:
            // High vol often accompanies strong trends
            regimeBias = 0.0
        case .ultra:
            // Ultra-high vol often marks exhaustion
            regimeBias = -0.1  // Slight bearish bias
        }

        // Structure contribution (-1 to 1)
        let structureBias: Double
        switch structureDirection {
        case .strongBullish: structureBias = 1.0
        case .bullish: structureBias = 0.7
        case .neutral: structureBias = 0.0
        case .bearish: structureBias = -0.7
        case .strongBearish: structureBias = -1.0
        }

        // Signal direction contribution (-1 to 1)
        let signalBias: Double
        switch signalDirection {
        case .strongBullish: signalBias = 1.0
        case .bullish: signalBias = 0.7
        case .neutral: signalBias = 0.0
        case .bearish: signalBias = -0.7
        case .strongBearish: signalBias = -1.0
        }

        // Agreement = how closely structure and signal align, with regime as modifier
        let baseAgreement = (structureBias + signalBias) / 2.0
        let regimeModifier = regimeBias * abs(baseAgreement)

        return max(-1.0, min(1.0, baseAgreement + regimeModifier))
    }

    // MARK: - Disagreement Classification

    private func classifyDisagreement(
        regime: Microstructure.VolatilityRegime,
        structureDirection: Direction,
        signalDirection: Direction
    ) -> RegimeStructureAnalysis.DisagreementType {
        // Check for direct conflicts
        if structureDirection.isBullish && signalDirection.isBearish {
            return .conflicting
        }
        if structureDirection.isBearish && signalDirection.isBullish {
            return .conflicting
        }

        // Check for weak structure
        if structureDirection == .neutral {
            return .structureWeak
        }

        // Check for regime mismatches
        switch regime {
        case .calm:
            // Calm markets with strong directional signals may be suspicious
            if signalDirection != .neutral {
                return .regimeMismatch
            }
        case .ultra:
            // Ultra-high vol with calm structure signals is suspicious
            if structureDirection == .neutral && signalDirection != .neutral {
                return .regimeMismatch
            }
        default:
            break
        }

        // Check if all agree
        if (structureDirection.isBullish && signalDirection.isBullish) ||
           (structureDirection.isBearish && signalDirection.isBearish) {
            return .agreement
        }

        return .neutral
    }

    // MARK: - Filter Configuration

    /// Reset to default configuration
    func reset() {
        config = RegimeFilterConfig()
    }

    /// Apply conservative preset (more filtering)
    func applyConservativePreset() {
        config.enabled = true
        config.minAgreementScore = 0.5
        config.contradictionPenalty = 0.2
        config.hardSuppression = true
    }

    /// Apply aggressive preset (less filtering)
    func applyAggressivePreset() {
        config.enabled = true
        config.minAgreementScore = 0.1
        config.contradictionPenalty = 0.05
        config.hardSuppression = false
    }
}

// MARK: - SwiftUI Settings View

import SwiftUI

struct RegimeFilterSettingsView: View {
    @ObservedObject private var filter = RegimeAwareSignalFilter.shared

    var body: some View {
        Form {
            Section(header: Text("Regime-Aware Filtering")) {
                Toggle("Enable Regime Filtering", isOn: $filter.config.enabled)

                if filter.config.enabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum Agreement Score: \(String(format: "%.2f", filter.config.minAgreementScore))")
                            .font(.subheadline)
                        Text("Signals with lower agreement are filtered out")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $filter.config.minAgreementScore, in: 0.0...0.8, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contradiction Penalty: \(String(format: "%.0f%%", filter.config.contradictionPenalty * 100))")
                            .font(.subheadline)
                        Text("Confidence reduction when regime contradicts signal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $filter.config.contradictionPenalty, in: 0.0...0.5, step: 0.05)
                    }

                    Toggle("Hard Suppression", isOn: $filter.config.hardSuppression)
                    Text("When enabled, conflicting signals are completely suppressed instead of penalized")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Structure Detection")) {
                Stepper("Structure Lookback: \(filter.config.structureLookback) candles",
                        value: $filter.config.structureLookback, in: 20...100, step: 10)
                Text("Higher lookback = smoother structure detection but slower response")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Presets")) {
                Button("Conservative (Strict Filtering)") {
                    filter.applyConservativePreset()
                }
                .foregroundColor(.orange)

                Button("Aggressive (Lenient Filtering)") {
                    filter.applyAggressivePreset()
                }
                .foregroundColor(.blue)

                Button("Reset to Defaults") {
                    filter.reset()
                }
                .foregroundColor(.red)
            }

            Section(header: Text("How It Works")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Regime Detection")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Classifies market as Calm, Normal, High, or Ultra-High volatility")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("2. Structure Analysis")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Detects trend direction from higher highs/lows pattern")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("3. Agreement Scoring")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Compares regime, structure, and signal direction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("4. Filtering")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Suppresses or penalizes low-quality conflicting signals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Signal Engine Integration

extension SignalEngine {
    /// Generate signal with regime-aware filtering
    func generateFiltered(for md: MarketData, strategyName: String = "Regime-Filtered Council") -> TradingSignal? {
        // First generate the raw signal
        guard let rawSignal = generate(for: md, strategyName: strategyName) else {
            return nil
        }

        // Apply regime-aware filtering
        let filter = RegimeAwareSignalFilter.shared
        guard filter.config.enabled else {
            return rawSignal
        }

        // Get agent votes for analysis
        let votes = agents.filter { $0.isActive }.map { $0.analyze(md, analyzer.analyze(md)) }

        return filter.filterSignal(
            signal: rawSignal,
            candles: md.candles,
            agentVotes: votes
        )
    }
}
