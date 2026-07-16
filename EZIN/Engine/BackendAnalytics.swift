import Foundation

/// Additional deterministic backend analytics used by chat tools and signal triage.
extension BackendQuantEngine {
    struct MarketRegime {
        let bias: Direction
        let state: String
        let volatilityState: String
        let squeezeScore: Double
        let expansionRisk: Double
        let persistence: Double
        let efficiencyRatio: Double
        let realizedVolatility: Double
        let atrPercent: Double
        let recommendation: String
    }

    static func regime(_ md: MarketData) -> MarketRegime {
        let closes = md.closes
        guard closes.count >= 30 else {
            return MarketRegime(
                bias: .neutral,
                state: "Undetermined",
                volatilityState: "Unknown",
                squeezeScore: 0,
                expansionRisk: 0,
                persistence: 0,
                efficiencyRatio: 0,
                realizedVolatility: 0,
                atrPercent: 0,
                recommendation: "Need at least 30 candles to classify the market regime."
            )
        }

        let system = systematic(md)
        let stats = statistics(closes)
        let returns = regimeLogReturns(closes)
        let recentReturns = Array(returns.suffix(min(20, returns.count)))
        let vol = regimeStandardDeviation(recentReturns)
        let longVol = regimeStandardDeviation(Array(returns.suffix(min(60, returns.count))))
        let volRatio = longVol > 0 ? vol / longVol : 1

        let tr = zip(md.highs, md.lows).map { $0.0 - $0.1 }
        let atr = regimeAverage(Array(tr.suffix(min(14, tr.count))))
        let price = closes.last ?? 0
        let atrPercent = price > 0 ? atr / price : 0

        let netMove = abs((closes.last ?? 0) - (closes.first ?? 0))
        let pathMove = zip(closes, closes.dropFirst()).reduce(0.0) { $0 + abs($1.1 - $1.0) }
        let efficiency = pathMove > 0 ? netMove / pathMove : 0

        let persistence = regimeClamp(0.5 + stats.autocorrelation * 0.35 + (system.trend * 0.15), 0, 1)
        let squeezeScore = regimeClamp((0.9 - min(volRatio, 1.8)) / 0.9, 0, 1)
        let expansionRisk = regimeClamp(max(0, volRatio - 1) * 0.8 + abs(system.breakout) * 0.2, 0, 1)

        let volatilityState: String
        if volRatio < 0.75 {
            volatilityState = "Compressed"
        } else if volRatio > 1.25 {
            volatilityState = "Expanded"
        } else {
            volatilityState = "Balanced"
        }

        let state: String
        if efficiency > 0.42 && abs(system.trend) > 0.25 {
            state = system.direction.isBullish ? "Trending up" : system.direction.isBearish ? "Trending down" : "Trending"
        } else if squeezeScore > 0.55 {
            state = "Coiling / squeeze"
        } else if abs(system.meanReversion) > 0.45 && abs(system.trend) < 0.20 {
            state = "Mean-reverting range"
        } else {
            state = "Transitional"
        }

        let recommendation: String
        switch state {
        case "Trending up":
            recommendation = "Favor continuation entries on pullbacks while volatility stays contained."
        case "Trending down":
            recommendation = "Favor sell-the-rally setups and tighten risk if volatility expands further."
        case "Coiling / squeeze":
            recommendation = "Expect a possible volatility release; wait for a confirmed break before committing risk."
        case "Mean-reverting range":
            recommendation = "Fade extremes near structure and avoid chasing mid-range breakouts."
        default:
            recommendation = "Signals are mixed; reduce size and wait for stronger structure or volatility confirmation."
        }

        return MarketRegime(
            bias: system.direction,
            state: state,
            volatilityState: volatilityState,
            squeezeScore: squeezeScore,
            expansionRisk: expansionRisk,
            persistence: persistence,
            efficiencyRatio: efficiency,
            realizedVolatility: vol,
            atrPercent: atrPercent,
            recommendation: recommendation
        )
    }

    static func regimeReport(for md: MarketData, symbol: String? = nil) -> String {
        let regime = regime(md)
        let name = (symbol?.isEmpty == false ? symbol! : md.symbol)
        return """
        ## Market Regime Report
        **Instrument:** \(name)
        - **Bias:** \(regimeLabel(regime.bias))
        - **State:** \(regime.state)
        - **Volatility:** \(regime.volatilityState)
        - **Persistence:** \(regimeNumber(regime.persistence))
        - **Efficiency ratio:** \(regimeNumber(regime.efficiencyRatio))
        - **Squeeze score:** \(regimeNumber(regime.squeezeScore))
        - **Expansion risk:** \(regimeNumber(regime.expansionRisk))
        - **Realized volatility:** \(regimeNumber(regime.realizedVolatility))
        - **ATR % of price:** \(regimeNumber(regime.atrPercent * 100))%

        **Actionable read:** \(regime.recommendation)
        """
    }

    private static func regimeLogReturns(_ prices: [Double]) -> [Double] {
        zip(prices, prices.dropFirst()).compactMap { $0.0 > 0 && $0.1 > 0 ? log($0.1 / $0.0) : nil }
    }

    private static func regimeAverage(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func regimeStandardDeviation(_ values: [Double]) -> Double {
        let mean = regimeAverage(values)
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(values.count - 1, 1)))
    }

    private static func regimeClamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static func regimeNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func regimeLabel(_ direction: Direction) -> String {
        switch direction {
        case .strongBullish: return "Strong bullish"
        case .bullish: return "Bullish"
        case .neutral: return "Neutral"
        case .bearish: return "Bearish"
        case .strongBearish: return "Strong bearish"
        }
    }
}
