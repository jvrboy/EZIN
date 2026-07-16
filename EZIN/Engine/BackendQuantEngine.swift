import Foundation

/// Deterministic, on-device quantitative backend used by the analysis agents.
/// It intentionally returns measurements and decision inputs—not executable trade orders.
enum BackendQuantEngine {
    struct SystematicScore {
        let trend: Double
        let meanReversion: Double
        let breakout: Double
        let momentum: Double
        let direction: Direction
        let strength: Int
        let confidence: Int
        let entryCondition: String
        let exitCondition: String
    }

    struct Statistics {
        let count: Int
        let mean: Double
        let standardDeviation: Double
        let skewness: Double
        let kurtosis: Double
        let zScore: Double
        let autocorrelation: Double
        let hurstExponent: Double
        let dominantPeriod: Int?
    }

    struct Randomness {
        let chiSquare: Double
        let entropy: Double
        let runsZScore: Double
        let transitionUpGivenUp: Double
        let transitionUpGivenDown: Double
        let biasDetected: Bool
    }

    struct RiskPlan {
        let stopDistance: Double
        let targetDistance: Double
        let riskReward: Double
        let kellyFraction: Double
        let cappedRiskFraction: Double
        let valueAtRisk: Double
        let conditionalValueAtRisk: Double
    }

    struct BacktestResult {
        let trades: Int
        let wins: Int
        let winRate: Double
        let netReturn: Double
        let maxDrawdown: Double
        let profitFactor: Double
    }

    static func systematic(_ md: MarketData) -> SystematicScore {
        let closes = md.closes
        guard closes.count >= 30, let price = closes.last else {
            return SystematicScore(trend: 0, meanReversion: 0, breakout: 0, momentum: 0, direction: .neutral, strength: 0, confidence: 0, entryCondition: "Need at least 30 candles", exitCondition: "No position")
        }
        let fast = average(Array(closes.suffix(10)))
        let slow = average(Array(closes.suffix(30)))
        let std = standardDeviation(Array(closes.suffix(20)))
        let z = std > 0 ? (price - average(Array(closes.suffix(20)))) / std : 0
        let high20 = closes.suffix(20).max() ?? price
        let low20 = closes.suffix(20).min() ?? price
        let range = max(high20 - low20, .leastNonzeroMagnitude)
        let momentum = clamp((price - (closes.dropLast(10).last ?? price)) / range, -1, 1)
        let trend = clamp((fast - slow) / max(std, abs(price) * 0.00001), -1, 1)
        let meanReversion = clamp(-z / 2, -1, 1)
        let breakout = clamp(((price - low20) / range - 0.5) * 2, -1, 1)
        let weighted = trend * 0.35 + momentum * 0.30 + breakout * 0.25 + meanReversion * 0.10
        let direction: Direction = weighted > 0.55 ? .strongBullish : weighted > 0.15 ? .bullish : weighted < -0.55 ? .strongBearish : weighted < -0.15 ? .bearish : .neutral
        let strength = Int((abs(weighted) * 100).rounded())
        let confidence = Int((min(1, abs(weighted) * 0.75 + min(1, abs(trend)) * 0.25) * 100).rounded())
        let entry = direction.isBullish ? "Close holds above fast trend baseline and momentum remains positive" : direction.isBearish ? "Close holds below fast trend baseline and momentum remains negative" : "Wait for a directional close outside the current balance"
        let exit = direction.isBullish ? "Exit on a close below the 10-bar mean or adverse 2 ATR move" : direction.isBearish ? "Exit on a close above the 10-bar mean or adverse 2 ATR move" : "No position"
        return SystematicScore(trend: trend, meanReversion: meanReversion, breakout: breakout, momentum: momentum, direction: direction, strength: strength, confidence: confidence, entryCondition: entry, exitCondition: exit)
    }

    static func statistics(_ prices: [Double]) -> Statistics {
        let returns = logReturns(prices)
        guard let latest = returns.last, returns.count >= 10 else {
            return Statistics(count: returns.count, mean: 0, standardDeviation: 0, skewness: 0, kurtosis: 0, zScore: 0, autocorrelation: 0, hurstExponent: 0.5, dominantPeriod: nil)
        }
        let meanValue = average(returns)
        let sd = standardDeviation(returns)
        let skew = moment(returns, order: 3, mean: meanValue) / pow(max(sd, .leastNonzeroMagnitude), 3)
        let kurt = moment(returns, order: 4, mean: meanValue) / pow(max(sd, .leastNonzeroMagnitude), 4) - 3
        return Statistics(count: returns.count, mean: meanValue, standardDeviation: sd, skewness: skew, kurtosis: kurt, zScore: sd > 0 ? (latest - meanValue) / sd : 0, autocorrelation: autocorrelation(returns, lag: 1), hurstExponent: hurst(prices), dominantPeriod: dominantPeriod(prices))
    }

    static func randomness(_ prices: [Double]) -> Randomness {
        let returns = logReturns(prices)
        guard returns.count >= 20 else { return Randomness(chiSquare: 0, entropy: 0, runsZScore: 0, transitionUpGivenUp: 0.5, transitionUpGivenDown: 0.5, biasDetected: false) }
        let signs = returns.map { $0 >= 0 }
        let up = signs.filter { $0 }.count
        let down = signs.count - up
        let expected = Double(signs.count) / 2
        let chi = expected > 0 ? (pow(Double(up) - expected, 2) + pow(Double(down) - expected, 2)) / expected : 0
        let pUp = Double(up) / Double(signs.count)
        let entropy = -(pUp > 0 ? pUp * log2(pUp) : 0) - (pUp < 1 ? (1 - pUp) * log2(1 - pUp) : 0)
        var runs = 1
        for index in 1..<signs.count where signs[index] != signs[index - 1] { runs += 1 }
        let n1 = Double(up), n2 = Double(down), n = n1 + n2
        let expectedRuns = 1 + 2 * n1 * n2 / n
        let varianceRuns = 2 * n1 * n2 * (2 * n1 * n2 - n) / max(n * n * (n - 1), 1)
        let runsZ = varianceRuns > 0 ? (Double(runs) - expectedRuns) / sqrt(varianceRuns) : 0
        let transitions = zip(signs, signs.dropFirst())
        let upAfterUp = transitions.filter { $0.0 }.map { $0.1 }
        let upAfterDown = transitions.filter { !$0.0 }.map { $0.1 }
        let pUU = upAfterUp.isEmpty ? 0.5 : Double(upAfterUp.filter { $0 }.count) / Double(upAfterUp.count)
        let pUD = upAfterDown.isEmpty ? 0.5 : Double(upAfterDown.filter { $0 }.count) / Double(upAfterDown.count)
        let bias = chi > 3.84 || abs(runsZ) > 1.96 || abs(pUU - pUD) > 0.20
        return Randomness(chiSquare: chi, entropy: entropy, runsZScore: runsZ, transitionUpGivenUp: pUU, transitionUpGivenDown: pUD, biasDetected: bias)
    }

    static func riskPlan(_ md: MarketData, winRate: Double = 0.5, payoffRatio: Double = 1.5, accountSize: Double = 0, maxRiskPercent: Double = 1) -> RiskPlan {
        let prices = md.closes
        let atr = average(zip(md.highs, md.lows).suffix(14).map { $0.0 - $0.1 })
        let fallback = (prices.last ?? 0) * 0.001
        let stop = max(atr * 2, fallback)
        let target = stop * payoffRatio
        let kelly = max(0, winRate - (1 - winRate) / max(payoffRatio, .leastNonzeroMagnitude))
        let capped = min(kelly, maxRiskPercent / 100)
        let returns = logReturns(prices)
        let sorted = returns.sorted()
        let tailCount = max(1, Int(Double(sorted.count) * 0.05))
        let varReturn = sorted.prefix(tailCount).last ?? 0
        let cvarReturn = average(Array(sorted.prefix(tailCount)))
        return RiskPlan(stopDistance: stop, targetDistance: target, riskReward: payoffRatio, kellyFraction: kelly, cappedRiskFraction: capped, valueAtRisk: abs(varReturn) * accountSize, conditionalValueAtRisk: abs(cvarReturn) * accountSize)
    }

    /// Conservative crossover replay; costs are charged on both entry and exit.
    static func backtest(_ prices: [Double], fast: Int = 10, slow: Int = 30, fee: Double = 0.0002) -> BacktestResult {
        guard prices.count > slow + 2 else { return BacktestResult(trades: 0, wins: 0, winRate: 0, netReturn: 0, maxDrawdown: 0, profitFactor: 0) }
        var position = 0.0, entry = 0.0, equity = 1.0, peak = 1.0, drawdown = 0.0, wins = 0, trades = 0, grossWin = 0.0, grossLoss = 0.0
        for i in slow..<prices.count {
            let f = average(Array(prices[(i - fast)...i]))
            let s = average(Array(prices[(i - slow)...i]))
            let wanted = f > s ? 1.0 : -1.0
            if position == 0 { position = wanted; entry = prices[i] }
            else if wanted != position {
                let result = position * (prices[i] - entry) / max(entry, .leastNonzeroMagnitude) - fee * 2
                equity *= max(0.01, 1 + result); trades += 1
                if result > 0 { wins += 1; grossWin += result } else { grossLoss += abs(result) }
                position = wanted; entry = prices[i]
            }
            peak = max(peak, equity); drawdown = max(drawdown, 1 - equity / peak)
        }
        return BacktestResult(trades: trades, wins: wins, winRate: trades > 0 ? Double(wins) / Double(trades) : 0, netReturn: equity - 1, maxDrawdown: drawdown, profitFactor: grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? .infinity : 0))
    }

    static func report(for md: MarketData, accountSize: Double = 0) -> String {
        let system = systematic(md), stats = statistics(md.closes), rng = randomness(md.closes)
        let risk = riskPlan(md, accountSize: accountSize), replay = backtest(md.closes)
        let period = stats.dominantPeriod.map(String.init) ?? "none"
        return """
        ## Quantitative Backend Report
        **Systematic direction:** \(label(system.direction)) · **Strength:** \(system.strength)/100 · **Confidence:** \(system.confidence)/100
        - Trend \(number(system.trend)) · momentum \(number(system.momentum)) · breakout \(number(system.breakout)) · mean reversion \(number(system.meanReversion))
        - **Entry:** \(system.entryCondition)
        - **Exit:** \(system.exitCondition)

        **Statistics:** σ \(number(stats.standardDeviation)) · z-score \(number(stats.zScore)) · skew \(number(stats.skewness)) · excess kurtosis \(number(stats.kurtosis)) · ACF(1) \(number(stats.autocorrelation)) · Hurst \(number(stats.hurstExponent)) · dominant cycle \(period) bars

        **Randomness diagnostics:** χ² \(number(rng.chiSquare)) · entropy \(number(rng.entropy))/1 · runs z \(number(rng.runsZScore)) · P(up|up) \(number(rng.transitionUpGivenUp)) · P(up|down) \(number(rng.transitionUpGivenDown)) · \(rng.biasDetected ? "statistical deviation flagged; validate out-of-sample" : "no material directional deviation detected")

        **Risk:** stop distance \(number(risk.stopDistance)) · target distance \(number(risk.targetDistance)) · R:R \(number(risk.riskReward)) · Kelly \(number(risk.kellyFraction * 100))% · capped risk \(number(risk.cappedRiskFraction * 100))% · 95% VaR \(number(risk.valueAtRisk)) · CVaR \(number(risk.conditionalValueAtRisk))

        **Crossover replay (not predictive):** \(replay.trades) closed trades · win rate \(number(replay.winRate * 100))% · net \(number(replay.netReturn * 100))% · max drawdown \(number(replay.maxDrawdown * 100))% · profit factor \(replay.profitFactor.isFinite ? number(replay.profitFactor) : "∞")
        """
    }

    private static func logReturns(_ prices: [Double]) -> [Double] { zip(prices, prices.dropFirst()).compactMap { $0.0 > 0 && $0.1 > 0 ? log($0.1 / $0.0) : nil } }
    private static func average(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    private static func standardDeviation(_ values: [Double]) -> Double { let m = average(values); return sqrt(values.reduce(0) { $0 + pow($1 - m, 2) } / Double(max(values.count - 1, 1))) }
    private static func moment(_ values: [Double], order: Int, mean: Double) -> Double { values.isEmpty ? 0 : values.reduce(0) { $0 + pow($1 - mean, Double(order)) } / Double(values.count) }
    private static func autocorrelation(_ values: [Double], lag: Int) -> Double { guard values.count > lag else { return 0 }; let m = average(values); let numerator = zip(values.dropFirst(lag), values.dropLast(lag)).reduce(0) { $0 + ($1.0 - m) * ($1.1 - m) }; let denominator = values.reduce(0) { $0 + pow($1 - m, 2) }; return denominator > 0 ? numerator / denominator : 0 }
    private static func hurst(_ prices: [Double]) -> Double { let returns = logReturns(prices); guard returns.count >= 20 else { return 0.5 }; let meanValue = average(returns); var cumulative = 0.0, minC = 0.0, maxC = 0.0; for value in returns { cumulative += value - meanValue; minC = min(minC, cumulative); maxC = max(maxC, cumulative) }; let sd = standardDeviation(returns); guard sd > 0, maxC > minC else { return 0.5 }; return clamp(log((maxC - minC) / sd) / log(Double(returns.count)), 0, 1) }
    private static func dominantPeriod(_ prices: [Double]) -> Int? { guard prices.count >= 40 else { return nil }; let returns = logReturns(prices); let candidates = (5...min(40, returns.count / 2)).map { ($0, abs(autocorrelation(returns, lag: $0))) }; return candidates.max { $0.1 < $1.1 }?.0 }
    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double { min(max(value, lower), upper) }
    private static func number(_ value: Double) -> String { String(format: "%.3f", value) }
    private static func label(_ direction: Direction) -> String { switch direction { case .strongBullish: return "Strong bullish"; case .bullish: return "Bullish"; case .neutral: return "Neutral"; case .bearish: return "Bearish"; case .strongBearish: return "Strong bearish" } }
}

extension MarketData {
    /// Safe convenience initializer for chart-only consumers that have candle data but no active quote.
    init(candles: [Candle]) {
        self.init(symbol: "", assetClass: .synthetic, timeframe: .m1, candles: candles, currentPrice: candles.last?.close ?? 0, bid: 0, ask: 0)
    }
}
