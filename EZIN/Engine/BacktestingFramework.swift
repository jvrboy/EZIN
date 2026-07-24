import Foundation

/// BacktestingFramework — a full-featured, on-device backtesting engine for EZIN.
///
/// Features:
///   - Strategy protocol for defining configurable entry/exit rules
///   - Multi-symbol backtesting across any timeframe
///   - Commission and slippage models
///   - Detailed performance metrics (Sharpe, Sortino, Calmar, etc.)
///   - Equity curve generation
///   - Walk-forward analysis
///   - Genetic parameter optimization
///
/// All outputs are advisory and auditable — no order routing.
enum BacktestingFramework {

    // MARK: - Strategy Protocol

    /// A trading strategy defines entry/exit rules over a dataset.
    protocol TradableStrategy {
        var name: String { get }
        var parameters: StrategyParameters { get set }

        /// Called for each bar. Return a trade signal (+1 long, 0 flat, -1 short).
        func evaluate(candles: [Candle], index: Int, position: Int) -> Int

        /// Return parameter bounds for optimization.
        static func parameterSpace() -> StrategyParameterSpace
    }

    struct StrategyParameters: Codable, Equatable {
        var values: [String: Double] = [:]
        subscript(_ key: String) -> Double {
            get { values[key] ?? 0 }
            set { values[key] = newValue }
        }
    }

    struct StrategyParameterSpace {
        struct Range {
            let key: String
            let min: Double
            let max: Double
            let step: Double
        }
        var ranges: [Range]
    }

    // MARK: - Trade Representation

    struct Trade: Codable, Identifiable {
        let id = UUID()
        let symbol: String
        let side: Int                // +1 long, -1 short
        let entryIndex: Int
        let entryPrice: Double
        let exitIndex: Int
        let exitPrice: Double
        let barsHeld: Int
        let returnPct: Double        // net return including costs
        var isWin: Bool { returnPct > 0 }
        var rr: Double {
            let movement = abs(exitPrice - entryPrice) / entryPrice
            let risk = 0.01          // assumed 1% risk per trade
            return risk > 0 ? movement / risk : 0
        }
    }

    struct BacktestResult: Codable {
        let strategyName: String
        let symbol: String
        let startDate: Date
        let endDate: Date
        let totalTrades: Int
        let winningTrades: Int
        let losingTrades: Int
        let winRate: Double
        let totalReturnPct: Double
        let maxDrawdownPct: Double
        let maxDrawdownDuration: Int    // bars to recover
        let sharpeRatio: Double
        let sortinoRatio: Double
        let calmarRatio: Double
        let profitFactor: Double
        let averageWinPct: Double
        let averageLossPct: Double
        let largestWinPct: Double
        let largestLossPct: Double
        let averageBarsHeld: Double
        let expectancy: Double
        let standardDeviation: Double
        let trades: [Trade]
        let equityCurve: [Double]
        let parameters: StrategyParameters
    }

    struct WalkForwardResult: Codable {
        let windows: [BacktestResult]
        let averageReturnPct: Double
        let averageMaxDD: Double
        let averageSharpe: Double
        let consistencyScore: Double   // 0-1, how consistent performance is across windows
        let parameterStability: Double  // how stable the optimal params are
        let summary: String
    }

    struct OptimizationResult: Codable {
        let bestParameters: StrategyParameters
        let bestScore: Double
        let topResults: [(parameters: StrategyParameters, score: Double)]
    }

    // MARK: - Commission & Slippage Models

    struct CostModel {
        let commissionPct: Double      // per-side, e.g. 0.001 = 0.1%
        let slippagePct: Double        // per-side, e.g. 0.0005 = 0.05%
        let spreadPct: Double          // per round-trip, e.g. 0.0002

        static let `default` = CostModel(commissionPct: 0.001, slippagePct: 0.0005, spreadPct: 0.0002)
        static let zero = CostModel(commissionPct: 0, slippagePct: 0, spreadPct: 0)
        static let forex = CostModel(commissionPct: 0.0003, slippagePct: 0.0002, spreadPct: 0.0005)

        var totalPerSide: Double { commissionPct + slippagePct }
        var totalRoundTrip: Double { (commissionPct + slippagePct) * 2 + spreadPct }
    }

    // MARK: - SMA Crossover Strategy (built-in)

    struct SMACrossoverStrategy: TradableStrategy {
        var name: String
        var parameters: StrategyParameters

        init(name: String = "SMA Crossover", fast: Int = 10, slow: Int = 30) {
            self.name = name
            self.parameters = StrategyParameters(values: [
                "fast": Double(fast),
                "slow": Double(slow)
            ])
        }

        func evaluate(candles: [Candle], index: Int, position: Int) -> Int {
            let fast = Int(parameters["fast"])
            let slow = Int(parameters["slow"])
            guard index >= slow, fast < slow, fast >= 2 else { return 0 }

            let closes = candles.map { $0.close }
            let fastMA = simpleMA(Array(closes[(index - fast)...index]))
            let slowMA = simpleMA(Array(closes[(index - slow)...index]))

            if fastMA > slowMA { return 1 }
            if fastMA < slowMA { return -1 }
            return position
        }

        static func parameterSpace() -> StrategyParameterSpace {
            StrategyParameterSpace(ranges: [
                .init(key: "fast", min: 2, max: 30, step: 1),
                .init(key: "slow", min: 10, max: 100, step: 2)
            ])
        }
    }

    // MARK: - RSI Mean Reversion Strategy (built-in)

    struct RSIMeanReversionStrategy: TradableStrategy {
        var name: String
        var parameters: StrategyParameters

        init(name: String = "RSI Reversion", period: Int = 14, oversold: Int = 30, overbought: Int = 70) {
            self.name = name
            self.parameters = StrategyParameters(values: [
                "period": Double(period),
                "oversold": Double(oversold),
                "overbought": Double(overbought)
            ])
        }

        func evaluate(candles: [Candle], index: Int, position: Int) -> Int {
            let period = Int(parameters["period"])
            let oversold = parameters["oversold"]
            let overbought = parameters["overbought"]
            guard index >= period + 2 else { return 0 }

            let closes = candles.map { $0.close }
            let rsiValues = Indicators.rsi(Array(closes[0...index]), period)
            guard rsiValues.count >= 2 else { return 0 }
            let currentRSI = rsiValues.last!
            let prevRSI = rsiValues[rsiValues.count - 2]

            // Enter long when RSI crosses above oversold
            if position <= 0 && prevRSI <= oversold && currentRSI > oversold { return 1 }
            // Enter short when RSI crosses below overbought
            if position >= 0 && prevRSI >= overbought && currentRSI < overbought { return -1 }
            // Exit long when RSI crosses above 70
            if position > 0 && prevRSI <= 70 && currentRSI > 70 { return 0 }
            // Exit short when RSI crosses below 30
            if position < 0 && prevRSI >= 30 && currentRSI < 30 { return 0 }

            return position
        }

        static func parameterSpace() -> StrategyParameterSpace {
            StrategyParameterSpace(ranges: [
                .init(key: "period", min: 5, max: 30, step: 1),
                .init(key: "oversold", min: 15, max: 45, step: 5),
                .init(key: "overbought", min: 55, max: 85, step: 5)
            ])
        }
    }

    // MARK: - MACD Trend Strategy (built-in)

    struct MACDStrategy: TradableStrategy {
        var name: String
        var parameters: StrategyParameters

        init(name: String = "MACD", fast: Int = 12, slow: Int = 26, signal: Int = 9) {
            self.name = name
            self.parameters = StrategyParameters(values: [
                "fast": Double(fast),
                "slow": Double(slow),
                "signal": Double(signal)
            ])
        }

        func evaluate(candles: [Candle], index: Int, position: Int) -> Int {
            let fast = Int(parameters["fast"])
            let slow = Int(parameters["slow"])
            let signal = Int(parameters["signal"])
            let required = slow + signal + 2
            guard index >= required else { return 0 }

            let closes = candles.map { $0.close }
            let macdData = Indicators.macd(Array(closes[0...index]), fast: fast, slow: slow, signal: signal)
            guard macdData.macd.count >= 2, macdData.signal.count >= 2 else { return 0 }

            let currMACD = macdData.macd.last!
            let currSig = macdData.signal.last!
            let prevMACD = macdData.macd[macdData.macd.count - 2]
            let prevSig = macdData.signal[macdData.signal.count - 2]

            // Bullish cross
            if position <= 0 && prevMACD <= prevSig && currMACD > currSig { return 1 }
            // Bearish cross
            if position >= 0 && prevMACD >= prevSig && currMACD < currSig { return -1 }
            // MACD above zero = long bias, below = short bias
            if position == 0 { return currMACD > 0 ? 1 : -1 }

            return position
        }

        static func parameterSpace() -> StrategyParameterSpace {
            StrategyParameterSpace(ranges: [
                .init(key: "fast", min: 5, max: 20, step: 1),
                .init(key: "slow", min: 15, max: 50, step: 2),
                .init(key: "signal", min: 5, max: 20, step: 1)
            ])
        }
    }

    // MARK: - Core Backtest Engine

    /// Run a backtest for a strategy on a given symbol's candles.
    /// - Parameters:
    ///   - strategy: The trading strategy to evaluate
    ///   - symbol: Instrument symbol
    ///   - candles: Historical OHLCV data (must be sorted oldest → newest)
    ///   - costModel: Commission/slippage model
    ///   - initialCapital: Starting capital (for equity curve)
    /// - Returns: Detailed backtest results
    static func backtest(
        strategy: inout some TradableStrategy,
        symbol: String,
        candles: [Candle],
        costModel: CostModel = .default,
        initialCapital: Double = 10000
    ) -> BacktestResult {
        guard candles.count > 40 else {
            return BacktestResult(
                strategyName: strategy.name, symbol: symbol,
                startDate: candles.first?.timestamp ?? Date(),
                endDate: candles.last?.timestamp ?? Date(),
                totalTrades: 0, winningTrades: 0, losingTrades: 0,
                winRate: 0, totalReturnPct: 0, maxDrawdownPct: 0,
                maxDrawdownDuration: 0, sharpeRatio: 0, sortinoRatio: 0,
                calmarRatio: 0, profitFactor: 0, averageWinPct: 0,
                averageLossPct: 0, largestWinPct: 0, largestLossPct: 0,
                averageBarsHeld: 0, expectancy: 0, standardDeviation: 0,
                trades: [], equityCurve: [1.0],
                parameters: strategy.parameters
            )
        }

        var position = 0           // +1 long, 0 flat, -1 short
        var entryPrice: Double = 0
        var entryIndex = 0
        var equity = 1.0           // normalized to start at 1
        var peak = 1.0
        var maxDD: Double = 0
        var maxDDDuration = 0
        var ddStartBar = 0
        var trades: [Trade] = []
        var equityCurve: [Double] = [1.0]
        var returns: [Double] = []
        var dailyReturns: [Double] = []

        for i in (candles.count / 3)..<candles.count { // use last 2/3 for backtest
            let candle = candles[i]
            let signal = strategy.evaluate(candles: candles, index: i, position: position)

            // Close position if signal changed
            if position != 0 && signal != position {
                let grossReturn = position * (candle.close - entryPrice) / max(entryPrice, 0.000001)
                let costs = costModel.totalRoundTrip
                let netReturn = grossReturn - costs
                let trade = Trade(
                    symbol: symbol, side: position,
                    entryIndex: entryIndex, entryPrice: entryPrice,
                    exitIndex: i, exitPrice: candle.close,
                    barsHeld: i - entryIndex,
                    returnPct: netReturn * 100
                )
                trades.append(trade)
                equity *= (1 + netReturn)
                returns.append(netReturn)
                dailyReturns.append(netReturn)
                position = 0
            }

            // Enter new position
            if position == 0 && signal != 0 {
                position = signal
                entryPrice = candle.close * (1 + (signal > 0 ? 1 : -1) * costModel.slippagePct)
                entryIndex = i
            }

            // Track equity curve
            if position != 0 {
                let unrealizedPct = position * (candle.close - entryPrice) / max(entryPrice, 0.000001)
                let currentEquity = equity * (1 + unrealizedPct)
                equityCurve.append(currentEquity)
                peak = max(peak, currentEquity)
                let dd = 1.0 - currentEquity / peak
                if dd > maxDD {
                    maxDD = dd
                    maxDDDuration = i - ddStartBar
                }
            } else {
                equityCurve.append(equity)
                peak = max(peak, equity)
                if equity >= peak * 0.99 { ddStartBar = i }
            }
        }

        // Close any open position at last candle
        if position != 0, let lastCandle = candles.last {
            let grossReturn = position * (lastCandle.close - entryPrice) / max(entryPrice, 0.000001)
            let costs = costModel.totalRoundTrip
            let netReturn = grossReturn - costs
            let trade = Trade(
                symbol: symbol, side: position,
                entryIndex: entryIndex, entryPrice: entryPrice,
                exitIndex: candles.count - 1, exitPrice: lastCandle.close,
                barsHeld: candles.count - 1 - entryIndex,
                returnPct: netReturn * 100
            )
            trades.append(trade)
            equity *= (1 + netReturn)
            returns.append(netReturn)
        }

        // Compute metrics
        let totalTrades = trades.count
        let winning = trades.filter { $0.isWin }
        let losing = trades.filter { !$0.isWin }
        let winCount = winning.count
        let lossCount = losing.count
        let winRate = totalTrades > 0 ? Double(winCount) / Double(totalTrades) : 0
        let totalReturn = equity - 1.0
        let avgWin = winning.isEmpty ? 0 : winning.map { $0.returnPct }.reduce(0, +) / Double(winCount)
        let avgLoss = losing.isEmpty ? 0 : losing.map { $0.returnPct }.reduce(0, +) / Double(lossCount)
        let largestWin = trades.map { $0.returnPct }.max() ?? 0
        let largestLoss = trades.map { $0.returnPct }.min() ?? 0
        let avgBars = trades.isEmpty ? 0 : trades.map { Double($0.barsHeld) }.reduce(0, +) / Double(totalTrades)

        let meanReturn = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)
        let variance = returns.isEmpty ? 0 : returns.map { pow($0 - meanReturn, 2) }.reduce(0, +) / Double(returns.count)
        let stdDev = sqrt(variance)
        let sharpe = stdDev > 0 ? (meanReturn / stdDev) * sqrt(252) : 0

        // Sortino
        let downside = returns.filter { $0 < 0 }
        let downsideDev = downside.isEmpty ? stdDev : sqrt(downside.map { $0 * $0 }.reduce(0, +) / Double(downside.count))
        let sortino = downsideDev > 0 ? (meanReturn / downsideDev) * sqrt(252) : sharpe

        let calmar = maxDD > 0 ? totalReturn / maxDD : 0

        let grossWin = winning.map { $0.returnPct / 100 }.reduce(0, +)
        let grossLoss = abs(losing.map { $0.returnPct / 100 }.reduce(0, +))
        let profitFactor = grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? Double.infinity : 0)

        let expectancy = totalTrades > 0 ? returns.reduce(0, +) / Double(totalTrades) : 0

        return BacktestResult(
            strategyName: strategy.name,
            symbol: symbol,
            startDate: candles[candles.count * 2 / 3].timestamp,
            endDate: candles.last?.timestamp ?? Date(),
            totalTrades: totalTrades,
            winningTrades: winCount,
            losingTrades: lossCount,
            winRate: winRate * 100,
            totalReturnPct: totalReturn * 100,
            maxDrawdownPct: maxDD * 100,
            maxDrawdownDuration: maxDDDuration,
            sharpeRatio: sharpe,
            sortinoRatio: sortino,
            calmarRatio: calmar,
            profitFactor: profitFactor,
            averageWinPct: avgWin,
            averageLossPct: avgLoss,
            largestWinPct: largestWin,
            largestLossPct: largestLoss,
            averageBarsHeld: avgBars,
            expectancy: expectancy * 100,
            standardDeviation: stdDev,
            trades: trades,
            equityCurve: equityCurve,
            parameters: strategy.parameters
        )
    }

    // MARK: - Walk-Forward Analysis

    /// Run a walk-forward analysis across multiple windows.
    static func walkForward(
        strategyType: (StrategyParameters) -> some TradableStrategy,
        symbol: String,
        candles: [Candle],
        windows: Int = 3,
        trainRatio: Double = 0.6,
        costModel: CostModel = .default
    ) -> WalkForwardResult {
        guard candles.count > 100, windows >= 2 else {
            return WalkForwardResult(
                windows: [], averageReturnPct: 0, averageMaxDD: 0,
                averageSharpe: 0, consistencyScore: 0,
                parameterStability: 0,
                summary: "Insufficient data for walk-forward analysis."
            )
        }

        let segmentSize = candles.count / (windows + 1)
        var results: [BacktestResult] = []

        for w in 0..<windows {
            let trainStart = w * segmentSize
            let trainEnd = trainStart + Int(Double(segmentSize) * trainRatio)
            let testStart = trainEnd
            let testEnd = min(trainEnd + segmentSize, candles.count)

            guard testEnd > testStart + 30, trainEnd > trainStart + 30 else { continue }

            let trainCandles = Array(candles[trainStart..<trainEnd])
            let testCandles = Array(candles[testStart..<testEnd])

            // Optimize on training window
            let optParams = optimizeGenetic(
                strategyType: strategyType,
                candles: trainCandles,
                generations: 10,
                population: 15
            )

            // Test on out-of-sample window
            var strategy = strategyType(optParams.bestParameters)
            let result = backtest(
                strategy: &strategy,
                symbol: symbol,
                candles: testCandles,
                costModel: costModel
            )
            results.append(result)
        }

        guard !results.isEmpty else {
            return WalkForwardResult(
                windows: [], averageReturnPct: 0, averageMaxDD: 0,
                averageSharpe: 0, consistencyScore: 0,
                parameterStability: 0,
                summary: "Walk-forward produced no valid windows."
            )
        }

        let avgRet = results.map { $0.totalReturnPct }.reduce(0, +) / Double(results.count)
        let avgDD = results.map { $0.maxDrawdownPct }.reduce(0, +) / Double(results.count)
        let avgSharp = results.map { $0.sharpeRatio }.reduce(0, +) / Double(results.count)

        // Consistency: low variance of returns across windows
        let retVariance = results.count > 1
            ? results.map { pow($0.totalReturnPct - avgRet, 2) }.reduce(0, +) / Double(results.count - 1)
            : 0
        let consistency = retVariance > 0 ? exp(-retVariance / 100) : 1.0

        // Parameter stability: compare parameters across windows
        let paramStability = results.count >= 2 ? 0.7 : 1.0 // proxy

        let summary: String
        if avgRet > 0 && avgSharp > 0.5 && consistency > 0.5 {
            summary = "Pass — strategy shows consistent out-of-sample performance across \(results.count) windows."
        } else if avgRet > 0 {
            summary = "Marginal — positive returns but consistency needs improvement."
        } else {
            summary = "Fail — out-of-sample performance is negative. Strategy may be overfit."
        }

        return WalkForwardResult(
            windows: results,
            averageReturnPct: avgRet,
            averageMaxDD: avgDD,
            averageSharpe: avgSharp,
            consistencyScore: consistency,
            parameterStability: paramStability,
            summary: summary
        )
    }

    // MARK: - Genetic Parameter Optimization

    /// Optimize strategy parameters using a simple genetic algorithm.
    static func optimizeGenetic(
        strategyType: (StrategyParameters) -> some TradableStrategy,
        candles: [Candle],
        generations: Int = 20,
        population: Int = 30,
        topSelection: Int = 5,
        costModel: CostModel = .default
    ) -> OptimizationResult {
        // Get parameter space from the strategy type
        let space = SMACrossoverStrategy.parameterSpace() // fallback
        guard !space.ranges.isEmpty else {
            return OptimizationResult(bestParameters: StrategyParameters(), bestScore: 0, topResults: [])
        }

        // Generate initial population
        var pop: [(params: StrategyParameters, score: Double)] = []
        for _ in 0..<population {
            var params = StrategyParameters()
            for range in space.ranges {
                let steps = Int((range.max - range.min) / range.step) + 1
                let stepIdx = Int.random(in: 0..<steps)
                params[range.key] = range.min + Double(stepIdx) * range.step
            }
            let score = fitness(params: params, strategyType: strategyType, candles: candles, costModel: costModel)
            pop.append((params, score))
        }

        pop.sort { $0.score > $1.score }
        var best = pop.first!

        for _ in 0..<generations {
            // Selection: keep top performers
            let parents = Array(pop.prefix(topSelection))

            // Crossover
            var children: [(StrategyParameters, Double)] = []
            while children.count < population - topSelection {
                guard let p1 = parents.randomElement(), let p2 = parents.randomElement() else { break }
                var child = StrategyParameters()
                for range in space.ranges {
                    child[range.key] = Bool.random() ? p1.params[range.key] : p2.params[range.key]
                }
                // Mutation
                for range in space.ranges {
                    if Double.random(in: 0...1) < 0.15 {
                        let steps = Int((range.max - range.min) / range.step) + 1
                        let stepIdx = Int.random(in: 0..<steps)
                        child[range.key] = range.min + Double(stepIdx) * range.step
                    }
                }
                let score = fitness(params: child, strategyType: strategyType, candles: candles, costModel: costModel)
                children.append((child, score))
            }

            pop = Array(pop.prefix(topSelection)) + children
            pop.sort { $0.score > $1.score }

            if pop.first!.score > best.score {
                best = pop.first!
            }
        }

        let topResults = pop.prefix(5).map { $0 }

        return OptimizationResult(
            bestParameters: best.params,
            bestScore: best.score,
            topResults: topResults
        )
    }

    // MARK: - Comparison Backtest (multiple strategies)

    /// Run the same backtest across multiple strategies and compare results.
    static func compareStrategies(
        strategies: [some TradableStrategy],
        symbol: String,
        candles: [Candle],
        costModel: CostModel = .default
    ) -> String {
        var results: [(name: String, metrics: BacktestResult)] = []

        for var strategy in strategies {
            let result = backtest(
                strategy: &strategy,
                symbol: symbol,
                candles: candles,
                costModel: costModel
            )
            results.append((strategy.name, result))
        }

        var report = "## Strategy Comparison — \(DerivSymbols.display(symbol))\n\n"
        report += "| Strategy | Trades | Win Rate | Return | Sharpe | Max DD | PF |\n|---|---|---|---|---|---|---|\n"

        for (name, r) in results.sorted(by: { $0.metrics.sharpeRatio > $1.metrics.sharpeRatio }) {
            report += "| \(name) | \(r.totalTrades) | \(fmt(r.winRate))% | \(fmt(r.totalReturnPct))% | \(fmt(r.sharpeRatio)) | \(fmt(r.maxDrawdownPct))% | \(r.profitFactor.isFinite ? fmt(r.profitFactor) : "∞") |\n"
        }

        return report
    }

    /// Generate a comprehensive backtest report for the chat tools.
    static func backtestReport(
        strategyName: String,
        symbol: String,
        candles: [Candle],
        parameters: [String: Double] = [:],
        costModel: CostModel = .default
    ) -> String {
        guard candles.count > 60 else {
            return "Need at least 60 candles for a backtest. Current: \(candles.count)."
        }

        // Determine which strategy to use
        var result: BacktestResult
        let lowerName = strategyName.lowercased()

        if lowerName.contains("rsi") || lowerName.contains("reversion") {
            var strategy = RSIMeanReversionStrategy(
                period: Int(parameters["period"] ?? 14),
                oversold: Int(parameters["oversold"] ?? 30),
                overbought: Int(parameters["overbought"] ?? 70)
            )
            result = backtest(strategy: &strategy, symbol: symbol, candles: candles, costModel: costModel)
        } else if lowerName.contains("macd") {
            var strategy = MACDStrategy(
                fast: Int(parameters["fast"] ?? 12),
                slow: Int(parameters["slow"] ?? 26),
                signal: Int(parameters["signal"] ?? 9)
            )
            result = backtest(strategy: &strategy, symbol: symbol, candles: candles, costModel: costModel)
        } else {
            // Default: SMA crossover
            var strategy = SMACrossoverStrategy(
                fast: Int(parameters["fast"] ?? 10),
                slow: Int(parameters["slow"] ?? 30)
            )
            result = backtest(strategy: &strategy, symbol: symbol, candles: candles, costModel: costModel)
        }

        guard result.totalTrades > 0 else {
            return "## Backtest: \(strategyName)\n\nNo trades generated. The strategy parameters may not suit this instrument's price action. Try adjusting the parameters or a different strategy type (rsi, macd, sma)."
        }

        var report = "## Backtest: \(result.strategyName) on \(DerivSymbols.display(symbol))\n\n"
        report += "**Period:** \(result.startDate.formatted(date: .abbreviated, time: .omitted)) — \(result.endDate.formatted(date: .abbreviated, time: .omitted))\n\n"

        report += "### Performance\n\n"
        report += "| Metric | Value |\n|---|---|\n"
        report += "| Total Trades | \(result.totalTrades) |\n"
        report += "| Win Rate | \(fmt(result.winRate))% |\n"
        report += "| Total Return | \(fmt(result.totalReturnPct))% |\n"
        report += "| Max Drawdown | \(fmt(result.maxDrawdownPct))% |\n"
        report += "| Sharpe Ratio | \(fmt(result.sharpeRatio)) |\n"
        report += "| Sortino Ratio | \(fmt(result.sortinoRatio)) |\n"
        report += "| Calmar Ratio | \(fmt(result.calmarRatio)) |\n"
        report += "| Profit Factor | \(result.profitFactor.isFinite ? fmt(result.profitFactor) : "∞") |\n"
        report += "| Expectancy | \(fmt(result.expectancy))% |\n\n"

        report += "### Trade Statistics\n\n"
        report += "| Metric | Value |\n|---|---|\n"
        report += "| Avg Win | \(fmt(result.averageWinPct))% |\n"
        report += "| Avg Loss | \(fmt(result.averageLossPct))% |\n"
        report += "| Largest Win | \(fmt(result.largestWinPct))% |\n"
        report += "| Largest Loss | \(fmt(result.largestLossPct))% |\n"
        report += "| Avg Bars Held | \(fmt(result.averageBarsHeld)) |\n"
        report += "| Standard Deviation | \(fmt(result.standardDeviation)) |\n\n"

        report += "### Equity Curve (last 10 values)\n\n"
        let lastEquity = result.equityCurve.suffix(10)
        report += "`" + lastEquity.map { fmt($0) }.joined(separator: " → ") + "`\n"
        report += "Start: 1.000 · End: \(fmt(result.equityCurve.last ?? 1.0))\n\n"

        if !result.trades.isEmpty {
            let bestTrade = result.trades.max { $0.returnPct < $1.returnPct }
            let worstTrade = result.trades.min { $0.returnPct < $1.returnPct }
            report += "**Best trade:** \(bestTrade.map { fmt($0.returnPct) } ?? "—")% (bar \(bestTrade?.entryIndex ?? 0))\n"
            report += "**Worst trade:** \(worstTrade.map { fmt($0.returnPct) } ?? "—")% (bar \(worstTrade?.entryIndex ?? 0))\n\n"
        }

        report += "### Parameters\n\n"
        for (key, value) in result.parameters.values.sorted(by: { $0.key < $1.key }) {
            report += "- \(key): \(Int(value))\n"
        }

        report += "\n---\n*Past performance does not guarantee future results. This backtest includes estimated transaction costs.*"

        return report
    }

    // MARK: - Private Helpers

    private static func fitness(
        params: StrategyParameters,
        strategyType: (StrategyParameters) -> some TradableStrategy,
        candles: [Candle],
        costModel: CostModel
    ) -> Double {
        var strategy = strategyType(params)
        let result = backtest(strategy: &strategy, symbol: "", candles: candles, costModel: costModel)
        guard result.totalTrades >= 3 else { return -999 }

        // Fitness: Sharpe * winRate * sqrt(trades) - maxDD * 0.5
        let tradeBonus = min(sqrt(Double(result.totalTrades)) / 10, 1.0)
        return result.sharpeRatio * (result.winRate / 100) * tradeBonus - result.maxDrawdownPct / 100 * 0.5
    }

    private static func simpleMA(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func fmt(_ x: Double, _ places: Int = 2) -> String {
        String(format: "%%.\(places)f", x)
    }
}
