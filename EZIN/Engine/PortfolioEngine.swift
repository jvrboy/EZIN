import Foundation

/// Portfolio Engine — multi-asset optimization and risk analytics for EZIN.
///
/// Provides institutional-grade portfolio tools running fully on-device:
///   - Mean-variance optimization (Markowitz efficient frontier)
///   - Risk parity allocation
///   - Kelly-optimal multi-asset sizing
///   - Portfolio-level metrics (Sharpe, Sortino, Calmar, diversification ratio)
///   - Correlation-aware risk decomposition
///   - Rebalancing suggestions
///
/// All outputs are advisory and auditable — no order routing.
enum PortfolioEngine {

    // MARK: - Data Structures

    /// A single asset in the portfolio with its historical returns.
    struct AssetInput {
        let symbol: String
        let prices: [Double]
    }

    /// Optimized allocation result.
    struct Allocation {
        let symbol: String
        let weight: Double  // 0...1 fractional allocation
    }

    /// Portfolio-level risk and return metrics.
    struct PortfolioMetrics {
        let expectedReturn: Double      // annualized expected return
        let volatility: Double          // annualized portfolio volatility
        let sharpeRatio: Double         // risk-free rate = 0
        let sortinoRatio: Double
        let calmarRatio: Double
        let maxDrawdown: Double
        let diversificationRatio: Double
        let concentration: Double       // Herfindahl index (1/n = max diversification)
        let valueAtRisk95: Double       // 95% VaR as fraction of portfolio
        let conditionalVaR95: Double    // 95% CVaR as fraction of portfolio
    }

    /// Efficient frontier sample point.
    struct FrontierPoint {
        let volatility: Double
        let expectedReturn: Double
        let sharpeRatio: Double
        let allocations: [Allocation]
    }

    /// Rebalancing recommendation.
    struct RebalanceSuggestion {
        let symbol: String
        let currentWeight: Double
        let targetWeight: Double
        let drift: Double               // absolute weight difference
        let action: String              // "buy", "sell", "hold"
        let urgency: String             // "immediate", "watch", "none"
    }

    /// Portfolio-level stress test result.
    struct StressTestResult {
        let scenario: String
        let impact: Double              // portfolio impact as fraction
        let maxDrawdown: Double
        let recoveryBars: Int           // estimated bars to recover
        let description: String
    }

    // MARK: - Mean-Variance Optimization

    /// Compute the efficient frontier for a set of assets.
    /// - Parameters:
    ///   - assets: Array of asset inputs with historical prices
    ///   - points: Number of frontier points to sample (default 50)
    /// - Returns: Array of frontier points from min-volatility to max-return
    static func efficientFrontier(assets: [AssetInput], points: Int = 50) -> [FrontierPoint] {
        guard assets.count >= 2 else { return [] }
        let returns = assets.map { logReturns($0.prices) }
        let n = assets.count

        // Compute return vector and covariance matrix
        let mu = returns.map { annualizedReturn(returns: $0) }
        let cov = covarianceMatrix(returns)

        // Generate random portfolios and keep the Pareto-optimal ones
        var frontier: [FrontierPoint] = []

        // Min-variance portfolio
        let minVar = minVariancePortfolio(cov: cov, mu: mu)
        frontier.append(contentsOf: frontierPoint(from: minVar, assets: assets, mu: mu, cov: cov))

        // Max-return portfolio (single asset with highest return)
        if let maxRetIdx = mu.enumerated().max(by: { $0.element < $1.element })?.offset {
            var maxRetWeights = [Double](repeating: 0, count: n)
            maxRetWeights[maxRetIdx] = 1.0
            let maxRetPoint = computePoint(weights: maxRetWeights, assets: assets, mu: mu, cov: cov)
            frontier.append(maxRetPoint)

            // Sample intermediate points along the frontier
            let minVarRet = minVar.expectedReturn
            let maxRet = mu[maxRetIdx]
            let step = (maxRet - minVarRet) / Double(max(points - 1, 1))

            for i in 1..<points {
                let targetRet = minVarRet + Double(i) * step
                if targetRet > maxRet { break }
                let w = minimumVarianceForTargetReturn(cov: cov, mu: mu, targetReturn: targetRet)
                if !w.isEmpty {
                    let pt = computePoint(weights: w, assets: assets, mu: mu, cov: cov)
                    frontier.append(pt)
                }
            }
        }

        // Sort by volatility and deduplicate
        return frontier.sorted { $0.volatility < $1.volatility }
    }

    /// Compute the optimal portfolio along the efficient frontier that maximizes Sharpe ratio.
    static func maxSharpePortfolio(assets: [AssetInput]) -> (allocations: [Allocation], metrics: PortfolioMetrics)? {
        guard assets.count >= 2 else { return nil }
        let returns = assets.map { logReturns($0.prices) }
        let mu = returns.map { annualizedReturn(returns: $0) }
        let cov = covarianceMatrix(returns)
        let n = assets.count

        // Use quadratic optimization to maximize Sharpe
        var bestSharpe: Double = -999
        var bestWeights: [Double] = []

        // Random search with many iterations
        for _ in 0..<5000 {
            var w = (0..<n).map { _ in Double.random(in: 0...1) }
            let sum = max(w.reduce(0, +), 0.000001)
            w = w.map { $0 / sum }

            let portRet = zip(w, mu).reduce(0) { $0 + $1.0 * $1.1 }
            let portVar = portfolioVariance(weights: w, cov: cov)
            let portVol = sqrt(max(portVar, 0.000001))
            let sharpe = portRet / portVol

            if sharpe > bestSharpe {
                bestSharpe = sharpe
                bestWeights = w
            }
        }

        guard !bestWeights.isEmpty else { return nil }
        let allocations = zip(assets, bestWeights).map { Allocation(symbol: $0.0.symbol, weight: $1.0) }
        let metrics = computeMetrics(weights: bestWeights, assets: assets, mu: mu, cov: cov)
        return (allocations, metrics)
    }

    /// Risk parity allocation — equal contribution to portfolio risk.
    static func riskParityPortfolio(assets: [AssetInput]) -> [Allocation]? {
        guard assets.count >= 2 else { return nil }
        let returns = assets.map { logReturns($0.prices) }
        let cov = covarianceMatrix(returns)
        let n = assets.count

        // Iterative risk parity: start from equal weights, adjust toward equal risk contribution
        var w = [Double](repeating: 1.0 / Double(n), count: n)
        let learningRate = 0.02

        for _ in 0..<200 {
            let portVar = portfolioVariance(weights: w, cov: cov)
            guard portVar > 0 else { break }

            // Marginal risk contribution per asset
            var mrc = [Double](repeating: 0, count: n)
            for i in 0..<n {
                var sum = 0.0
                for j in 0..<n {
                    sum += w[j] * cov[i][j]
                }
                mrc[i] = sum / sqrt(portVar)
            }

            // Total risk contribution
            let trc = zip(w, mrc).map { $0 * $1 }
            let targetRC = trc.reduce(0, +) / Double(n)

            // Adjust weights toward equal risk contribution
            for i in 0..<n {
                let deviation = (trc[i] - targetRC) / max(targetRC, 0.000001)
                w[i] *= 1.0 - learningRate * deviation
            }

            // Normalize
            let sum = max(w.reduce(0, +), 0.000001)
            w = w.map { $0 / sum }
        }

        return zip(assets, w).map { Allocation(symbol: $0.0.symbol, weight: $1.0) }
    }

    /// Kelly-optimal multi-asset allocation using historical wins/losses per symbol
    /// as a proxy for edge. Falls back to half-Kelly for safety.
    static func kellyPortfolio(assets: [AssetInput]) -> [Allocation]? {
        guard assets.count >= 1 else { return nil }

        var allocations: [Allocation] = []
        var totalKelly = 0.0

        for asset in assets {
            let r = logReturns(asset.prices)
            guard r.count >= 20 else { continue }

            // Estimate win rate and average win/loss from directional returns
            let wins = r.filter { $0 > 0 }
            let losses = r.filter { $0 < 0 }

            guard !wins.isEmpty, !losses.isEmpty else { continue }

            let winRate = Double(wins.count) / Double(r.count)
            let avgWin = wins.reduce(0, +) / Double(wins.count)
            let avgLoss = abs(losses.reduce(0, +) / Double(losses.count))
            let payoffRatio = avgLoss > 0 ? avgWin / avgLoss : 1.0

            // Full Kelly: f* = (p*b - q) / b where b = payoff ratio
            let kellyFraction = max(0, (winRate * payoffRatio - (1 - winRate)) / max(payoffRatio, 0.01))

            // Half-Kelly for safety
            let halfKelly = kellyFraction * 0.5

            allocations.append(Allocation(symbol: asset.symbol, weight: halfKelly))
            totalKelly += halfKelly
        }

        // Normalize to sum to 1.0 (or cap at 1.0)
        guard totalKelly > 0 else { return nil }
        if totalKelly > 1.0 {
            allocations = allocations.map { Allocation(symbol: $0.symbol, weight: $0.weight / totalKelly) }
        } else {
            // Add cash proportion
            let cash = 1.0 - totalKelly
            allocations.append(Allocation(symbol: "CASH", weight: cash))
        }

        return allocations
    }

    // MARK: - Portfolio Metrics

    /// Compute comprehensive portfolio metrics.
    static func portfolioMetrics(allocations: [Allocation], assets: [AssetInput]) -> PortfolioMetrics? {
        guard allocations.count == assets.count, !allocations.isEmpty else { return nil }
        let weights = allocations.map { $0.weight }
        let returns = assets.map { logReturns($0.prices) }
        let mu = returns.map { annualizedReturn(returns: $0) }
        let cov = covarianceMatrix(returns)
        return computeMetrics(weights: weights, assets: assets, mu: mu, cov: cov)
    }

    // MARK: - Rebalancing

    /// Compute rebalancing suggestions given current and target allocations.
    static func rebalanceSuggestions(
        currentAllocations: [Allocation],
        targetAllocations: [Allocation],
        driftThreshold: Double = 0.05
    ) -> [RebalanceSuggestion] {
        let targetMap = Dictionary(uniqueKeysWithValues: targetAllocations.map { ($0.symbol, $0.weight) })
        let currentMap = Dictionary(uniqueKeysWithValues: currentAllocations.map { ($0.symbol, $0.weight) })
        let allSymbols = Set(targetMap.keys).union(currentMap.keys)

        return allSymbols.compactMap { symbol -> RebalanceSuggestion? in
            let target = targetMap[symbol] ?? 0
            let current = currentMap[symbol] ?? 0
            let drift = abs(current - target)

            guard drift > 0.001 else { return nil }

            let action: String
            if current < target - driftThreshold { action = "buy" }
            else if current > target + driftThreshold { action = "sell" }
            else { action = "hold" }

            let urgency: String
            if drift > 0.15 { urgency = "immediate" }
            else if drift > 0.08 { urgency = "watch" }
            else { urgency = "none" }

            return RebalanceSuggestion(
                symbol: symbol,
                currentWeight: current,
                targetWeight: target,
                drift: drift,
                action: action,
                urgency: urgency
            )
        }.sorted { $0.drift > $1.drift }
    }

    // MARK: - Stress Testing

    /// Run portfolio-level stress tests.
    static func stressTest(allocations: [Allocation], assets: [AssetInput]) -> [StressTestResult] {
        guard !allocations.isEmpty, allocations.count == assets.count else { return [] }
        let returns = assets.map { logReturns($0.prices) }
        let weights = allocations.map { $0.weight }

        var results: [StressTestResult] = []

        // Scenario 1: 2008-style crash (-40% equities)
        let crashImpact = simulateScenario(weights: weights, returns: returns, shock: -0.40, affectedFraction: 0.7)
        results.append(StressTestResult(
            scenario: "2008-Style Crash",
            impact: crashImpact,
            maxDrawdown: abs(crashImpact),
            recoveryBars: Int(abs(crashImpact) / 0.002),  // ~0.2% per bar recovery
            description: "Simulated 40% drawdown across 70% of portfolio. Impact: \(String(format: "%.1f", crashImpact * 100))%"
        ))

        // Scenario 2: COVID-style shock (-30% rapid)
        let covidImpact = simulateScenario(weights: weights, returns: returns, shock: -0.30, affectedFraction: 0.8)
        results.append(StressTestResult(
            scenario: "COVID-Style Shock",
            impact: covidImpact,
            maxDrawdown: abs(covidImpact),
            recoveryBars: Int(abs(covidImpact) / 0.003),
            description: "Simulated 30% rapid drawdown across 80% of portfolio. Impact: \(String(format: "%.1f", covidImpact * 100))%"
        ))

        // Scenario 3: Volatility spike (3x vol)
        let volSpikeImpact = simulateVolatilitySpike(weights: weights, returns: returns)
        results.append(StressTestResult(
            scenario: "Volatility Spike (3x)",
            impact: volSpikeImpact,
            maxDrawdown: abs(volSpikeImpact),
            recoveryBars: Int(abs(volSpikeImpact) / 0.001),
            description: "Simulated 3x volatility expansion. Impact: \(String(format: "%.1f", volSpikeImpact * 100))%"
        ))

        // Scenario 4: Flash crash (-10% in one session)
        let flashImpact = simulateScenario(weights: weights, returns: returns, shock: -0.10, affectedFraction: 0.5)
        results.append(StressTestResult(
            scenario: "Flash Crash",
            impact: flashImpact,
            maxDrawdown: abs(flashImpact),
            recoveryBars: Int(abs(flashImpact) / 0.005),
            description: "Simulated 10% intraday crash across 50% of portfolio. Impact: \(String(format: "%.1f", flashImpact * 100))%"
        ))

        return results
    }

    // MARK: - Portfolio Analysis Report

    /// Generate a comprehensive portfolio analysis report for the chat tools.
    static func portfolioReport(assets: [AssetInput]) -> String {
        guard assets.count >= 2 else {
            if assets.count == 1 {
                let r = logReturns(assets[0].prices)
                let ret = annualizedReturn(returns: r)
                let vol = sqrt(252) * standardDeviation(r)
                return """
                ## Portfolio Analysis — Single Asset

                | Metric | Value |
                |---|---|
                | Symbol | \(assets[0].symbol) |
                | Expected Return (ann.) | \(fmt(ret)) |
                | Volatility (ann.) | \(fmt(vol)) |
                | Sharpe Ratio | \(ret > 0 && vol > 0 ? fmt(ret / vol) : "N/A") |
                | Samples | \(r.count) |

                Add at least 2 instruments to enable portfolio optimization, efficient frontier, risk parity, and Kelly allocation.
                """
            }
            return "## Portfolio Analysis\n\nNeed at least one instrument with cached candle data. Use `price(symbol)`, `analyze(symbol,timeframe)` or open the Chart tab to subscribe."
        }

        var report = "## Portfolio Analysis\n\n"

        // Max Sharpe portfolio
        if let (maxSharpeAlloc, maxSharpeMetrics) = maxSharpePortfolio(assets: assets) {
            report += "### Optimal Portfolio (Max Sharpe)\n\n"
            report += "| Metric | Value |\n|---|---|\n"
            report += "| Expected Return (ann.) | \(fmt(maxSharpeMetrics.expectedReturn)) |\n"
            report += "| Volatility (ann.) | \(fmt(maxSharpeMetrics.volatility)) |\n"
            report += "| Sharpe Ratio | \(fmt(maxSharpeMetrics.sharpeRatio)) |\n"
            report += "| Sortino Ratio | \(fmt(maxSharpeMetrics.sortinoRatio)) |\n"
            report += "| Calmar Ratio | \(fmt(maxSharpeMetrics.calmarRatio)) |\n"
            report += "| Max Drawdown | \(fmt(maxSharpeMetrics.maxDrawdown)) |\n"
            report += "| Diversification Ratio | \(fmt(maxSharpeMetrics.diversificationRatio)) |\n"
            report += "| Concentration (HHI) | \(fmt(maxSharpeMetrics.concentration)) |\n"
            report += "| 95% VaR | \(fmt(maxSharpeMetrics.valueAtRisk95)) |\n"
            report += "| 95% CVaR | \(fmt(maxSharpeMetrics.conditionalVaR95)) |\n\n"

            report += "**Allocations:**\n\n"
            report += "| Symbol | Weight |\n|---|---|\n"
            for alloc in maxSharpeAlloc.sorted(by: { $0.weight > $1.weight }) {
                report += "| \(DerivSymbols.display(alloc.symbol)) | \(fmt(alloc.weight)) |\n"
            }
        }

        // Risk parity
        if let rp = riskParityPortfolio(assets: assets) {
            report += "\n### Risk Parity Allocation\n\n"
            report += "| Symbol | Weight |\n|---|---|\n"
            for alloc in rp.sorted(by: { $0.weight > $1.weight }) {
                report += "| \(DerivSymbols.display(alloc.symbol)) | \(fmt(alloc.weight)) |\n"
            }
        }

        // Kelly allocation
        if let kelly = kellyPortfolio(assets: assets) {
            report += "\n### Kelly-Optimal Allocation (Half-Kelly)\n\n"
            report += "| Component | Weight |\n|---|---|\n"
            for alloc in kelly.sorted(by: { $0.weight > $1.weight }) {
                report += "| \(alloc.symbol == "CASH" ? "Cash Reserve" : DerivSymbols.display(alloc.symbol)) | \(fmt(alloc.weight)) |\n"
            }
        }

        // Efficient frontier summary
        let frontier = efficientFrontier(assets: assets, points: 20)
        if let minVol = frontier.first, let maxRet = frontier.last {
            report += "\n### Efficient Frontier\n\n"
            report += "| Point | Volatility | Return | Sharpe |\n|---|---|---|---|\n"
            report += "| Min Volatility | \(fmt(minVol.volatility)) | \(fmt(minVol.expectedReturn)) | \(fmt(minVol.sharpeRatio)) |\n"
            report += "| Max Return | \(fmt(maxRet.volatility)) | \(fmt(maxRet.expectedReturn)) | \(fmt(maxRet.sharpeRatio)) |\n"
            report += "| Frontier Points | \(frontier.count) | | |\n"
        }

        // Stress tests
        let allocations = maxSharpePortfolio(assets: assets)?.allocations ?? assets.map { Allocation(symbol: $0.symbol, weight: 1.0 / Double(assets.count)) }
        let stress = stressTest(allocations: allocations, assets: assets)
        report += "\n### Stress Tests\n\n"
        report += "| Scenario | Portfolio Impact | Max DD | Est. Recovery |\n|---|---|---|---|\n"
        for test in stress {
            report += "| \(test.scenario) | \(fmt(test.impact)) | \(fmt(test.maxDrawdown)) | ~\(test.recoveryBars) bars |\n"
        }

        report += "\n---\n*Portfolio analysis is advisory only. Allocations are not trade recommendations. Use in conjunction with structure, regime, and risk analysis before any deployment.*"

        return report
    }

    // MARK: - Private Helpers

    private static func minVariancePortfolio(cov: [[Double]], mu: [Double]) -> (weights: [Double], expectedReturn: Double, variance: Double) {
        let n = cov.count
        var w = [Double](repeating: 1.0 / Double(n), count: n)
        let lr = 0.01

        for _ in 0..<500 {
            let grad = gradient(weights: w, cov: cov)
            for i in 0..<n {
                w[i] -= lr * grad[i]
                w[i] = max(w[i], 0.0001)
            }
            let sum = w.reduce(0, +)
            w = w.map { $0 / sum }
        }

        let ret = zip(w, mu).reduce(0) { $0 + $1.0 * $1.1 }
        let var_ = portfolioVariance(weights: w, cov: cov)
        return (w, ret, var_)
    }

    private static func minimumVarianceForTargetReturn(cov: [[Double]], mu: [Double], targetReturn: Double) -> [Double] {
        let n = cov.count
        var w = [Double](repeating: 1.0 / Double(n), count: n)
        let lr = 0.01
        let lambda = 2.0  // penalty multiplier for return deviation

        for _ in 0..<500 {
            let grad = gradient(weights: w, cov: cov)
            let currentRet = zip(w, mu).reduce(0) { $0 + $1.0 * $1.1 }
            let retPenalty = (currentRet - targetReturn) * lambda

            for i in 0..<n {
                w[i] -= lr * (grad[i] + retPenalty * mu[i])
                w[i] = max(w[i], 0.0001)
            }
            let sum = w.reduce(0, +)
            w = w.map { $0 / sum }
        }

        return w
    }

    private static func gradient(weights: [Double], cov: [[Double]]) -> [Double] {
        let n = weights.count
        var grad = [Double](repeating: 0, count: n)
        for i in 0..<n {
            for j in 0..<n {
                grad[i] += 2 * weights[j] * cov[i][j]
            }
        }
        return grad
    }

    private static func computePoint(weights: [Double], assets: [AssetInput], mu: [Double], cov: [[Double]]) -> FrontierPoint {
        let allocations = zip(assets, weights).map { Allocation(symbol: $0.0.symbol, weight: $1.0) }
        let metrics = computeMetrics(weights: weights, assets: assets, mu: mu, cov: cov)
        return FrontierPoint(
            volatility: metrics.volatility,
            expectedReturn: metrics.expectedReturn,
            sharpeRatio: metrics.sharpeRatio,
            allocations: allocations
        )
    }

    private static func frontierPoint(from point: (weights: [Double], expectedReturn: Double, variance: Double), assets: [AssetInput], mu: [Double], cov: [[Double]]) -> [FrontierPoint] {
        let allocations = zip(assets, point.weights).map { Allocation(symbol: $0.0.symbol, weight: $1.0) }
        let vol = sqrt(max(point.variance, 0.000001))
        let sharpe = point.expectedReturn / vol
        return [FrontierPoint(volatility: vol, expectedReturn: point.expectedReturn, sharpeRatio: sharpe, allocations: allocations)]
    }

    private static func computeMetrics(weights: [Double], assets: [AssetInput], mu: [Double], cov: [[Double]]) -> PortfolioMetrics {
        let n = weights.count
        let expRet = zip(weights, mu).reduce(0) { $0 + $1.0 * $1.1 }
        let var_ = portfolioVariance(weights: weights, cov: cov)
        let vol = sqrt(max(var_, 0.000001))
        let sharpe = expRet / vol

        // Sortino: use only downside deviation
        let returns = assets.map { logReturns($0.prices) }
        let minLen = returns.map { $0.count }.min() ?? 0
        var downsideSum = 0.0
        var downsideCount = 0
        if minLen > 1 {
            for i in 0..<n {
                let r = returns[i]
                for j in 0..<r.count {
                    if r[j] < 0 {
                        downsideSum += r[j] * r[j] * weights[i] * weights[i]
                        downsideCount += 1
                    }
                }
            }
        }
        let downsideDev = downsideCount > 0 ? sqrt(downsideSum / Double(downsideCount)) : vol
        let sortino = downsideDev > 0 ? expRet / downsideDev : sharpe

        // Max drawdown and Calmar
        var peak = 1.0, maxDD = 0.0, equity = 1.0
        if minLen > 1 {
            // Simulate portfolio equity curve
            for t in 0..<minLen {
                var dailyReturn = 0.0
                for i in 0..<n {
                    let r = returns[i]
                    if t < r.count {
                        dailyReturn += weights[i] * r[t]
                    }
                }
                equity *= exp(dailyReturn)
                peak = max(peak, equity)
                maxDD = max(maxDD, 1 - equity / peak)
            }
        }
        let calmar = maxDD > 0 ? expRet / maxDD : sharpe

        // Diversification ratio = sum(weights * vol_i) / portfolio_vol
        var weightedVolSum = 0.0
        for i in 0..<n {
            weightedVolSum += weights[i] * sqrt(max(cov[i][i], 0.000001))
        }
        let divRatio = weightedVolSum / vol

        // Concentration (HHI)
        let hhi = weights.reduce(0) { $0 + $1 * $1 }

        // VaR and CVaR from portfolio returns
        var portReturns: [Double] = []
        if minLen > 1 {
            for t in 0..<minLen {
                var r = 0.0
                for i in 0..<n {
                    let ri = returns[i]
                    if t < ri.count {
                        r += weights[i] * ri[t]
                    }
                }
                portReturns.append(r)
            }
        }
        let sorted = portReturns.sorted()
        let tailIdx95 = max(0, Int(Double(sorted.count) * 0.05))
        let tailIdx975 = max(0, Int(Double(sorted.count) * 0.025))
        let var95 = sorted.isEmpty ? 0 : sorted[min(tailIdx95, sorted.count - 1)]
        let cvar95: Double
        if sorted.isEmpty {
            cvar95 = 0
        } else {
            let tail = sorted.prefix(max(tailIdx975, 1))
            cvar95 = tail.reduce(0, +) / Double(tail.count)
        }

        return PortfolioMetrics(
            expectedReturn: expRet,
            volatility: vol,
            sharpeRatio: sharpe,
            sortinoRatio: sortino,
            calmarRatio: calmar,
            maxDrawdown: maxDD,
            diversificationRatio: divRatio,
            concentration: hhi,
            valueAtRisk95: abs(var95),
            conditionalVaR95: abs(cvar95)
        )
    }

    private static func portfolioVariance(weights: [Double], cov: [[Double]]) -> Double {
        let n = weights.count
        var var_ = 0.0
        for i in 0..<n {
            for j in 0..<n {
                var_ += weights[i] * weights[j] * cov[i][j]
            }
        }
        return var_
    }

    private static func covarianceMatrix(_ returns: [[Double]]) -> [[Double]] {
        let n = returns.count
        let minLen = returns.map { $0.count }.min() ?? 0
        guard minLen > 2 else { return [[Double]](repeating: [Double](repeating: 0, count: n), count: n) }

        var cov = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0..<n {
                let ri = Array(returns[i].suffix(minLen))
                let rj = Array(returns[j].suffix(minLen))
                cov[i][j] = covariance(ri, rj)
            }
        }
        return cov
    }

    private static func covariance(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 2 else { return 0 }
        let ma = a.reduce(0, +) / Double(n)
        let mb = b.reduce(0, +) / Double(n)
        return zip(a, b).reduce(0) { $0 + ($1.0 - ma) * ($1.1 - mb) } / Double(n - 1)
    }

    private static func annualizedReturn(returns: [Double]) -> Double {
        guard !returns.isEmpty else { return 0 }
        // Annualize from daily returns (252 trading days)
        let mu = returns.reduce(0, +) / Double(returns.count)
        return mu * 252
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = values.reduce(0, +) / Double(values.count)
        return sqrt(values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count - 1))
    }

    private static func logReturns(_ prices: [Double]) -> [Double] {
        zip(prices, prices.dropFirst()).compactMap { old, new in
            old > 0 && new > 0 ? log(new / old) : nil
        }
    }

    private static func simulateScenario(weights: [Double], returns: [[Double]], shock: Double, affectedFraction: Double) -> Double {
        let n = weights.count
        guard n > 0 else { return 0 }
        var portShock = 0.0
        for i in 0..<n {
            let affected = Bool.random(probability: affectedFraction)
            portShock += weights[i] * (affected ? shock : 0)
        }
        return portShock
    }

    private static func simulateVolatilitySpike(weights: [Double], returns: [[Double]]) -> Double {
        let n = weights.count
        guard n > 0, let minLen = returns.map({ $0.count }).min(), minLen > 5 else { return 0 }

        // Measure current vol, simulate 3x vol regime for 5 bars
        var volSpikeImpact = 0.0
        for i in 0..<n {
            let r = returns[i]
            let recent = Array(r.suffix(min(20, r.count)))
            let vol = standardDeviation(recent)
            let shockedVol = vol * 3

            // Expected move under shocked vol
            let shock = shockedVol * Double.random(in: -2...2)
            volSpikeImpact += weights[i] * shock
        }
        return volSpikeImpact
    }

    private static func fmt(_ x: Double, _ places: Int = 4) -> String {
        String(format: "%%.\(places)f", x)
    }
}

// MARK: - Random Bool with probability

private extension Bool {
    static func random(probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }
}
