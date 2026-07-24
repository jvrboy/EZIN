import Foundation

// MARK: - Position Calculator Models

/// Result of a position size calculation.
struct PositionSizeResult {
    let accountSize: Double
    let riskPercent: Double           // % of account to risk
    let riskAmount: Double            // currency amount at risk
    let stopLossPips: Double          // stop loss in pips/points
    let positionSize: Double          // units/stake
    let pipValue: Double              // value of one pip
    let maxPositionSize: Double       // max size without exceeding risk %
    let recommendedStake: Double      // recommended stake for this trade
    let marginRequired: Double        // margin needed
    let leverage: Double              // effective leverage
    let riskRewardRatio: Double       // if take profit is specified
    let potentialProfit: Double?      // if take profit is specified
    let marginLevel: Double           // used margin / available
}

/// Risk metrics for a trading plan.
struct RiskMetricsResult {
    let accountSize: Double
    let maxDailyLoss: Double          // 2% rule
    let maxWeeklyLoss: Double         // 5% rule
    let maxPositionRisk: Double       // 1% rule
    let kellyFraction: Double         // optimal Kelly %
    let halfKelly: Double             // conservative half-Kelly
    let var95: Double                 // Value at Risk (95%)
    let cvar95: Double                // Conditional VaR (95%)
    let maxConsecutiveLosses: Int     // suggested max losing streak to plan for
    let suggestedStopLossPct: Double  // suggested max stop as % of account
    let dailyLossLimit: Double        // stop trading when reached
    let weeklyLossLimit: Double       // stop trading when reached
}

/// Lot size mapping for forex and synthetic instruments.
struct LotSizeInfo {
    let standardLot: Double           // 1 standard lot = 100,000 units
    let miniLot: Double               // 1 mini lot = 10,000 units
    let microLot: Double              // 1 micro lot = 1,000 units
    let nanoLot: Double               // 1 nano lot = 100 units
    let currentLotSize: Double        // calculated position in lots
    let contractSize: Double          // contract size for the instrument
    let displayName: String
}

// MARK: - Position Calculator Service

/// On-device position sizing and risk management calculator.
/// Handles pip values, position sizing, margin, and risk/reward calculations
/// specifically for Deriv synthetic and forex instruments.
final class PositionCalculatorService {
    static let shared = PositionCalculatorService()

    private init() {}

    /// Calculate position size based on account size, risk %, and stop loss distance.
    func calculatePositionSize(
        accountSize: Double,
        riskPercent: Double,
        entryPrice: Double,
        stopLoss: Double,
        takeProfit: Double? = nil,
        currency: String = "USD",
        isForex: Bool = false
    ) -> PositionSizeResult {
        let clampedRisk = max(0.1, min(riskPercent, 10.0))  // 0.1% - 10%
        let riskAmount = accountSize * (clampedRisk / 100.0)
        let stopDistance = abs(entryPrice - stopLoss)
        let stopPips = stopDistance / (entryPrice * 0.0001)  // convert to pips

        // Calculate position size (stake)
        let positionSize: Double
        if stopDistance > 0 {
            positionSize = riskAmount / (stopDistance / entryPrice)
        } else {
            positionSize = 0
        }

        let pipValue = stopPips > 0 ? riskAmount / stopPips : 0
        let maxPosition = accountSize * 0.5  // don't risk > 50% of account in a single position
        let recommended = min(positionSize, maxPosition)

        // Margin calculation
        let leverage: Double = isForex ? 30.0 : 10.0  // typical Deriv leverage
        let marginRequired = recommended / leverage
        let marginLevel = marginRequired > 0 ? (accountSize / marginRequired) * 100 : 0

        // R:R
        let rr: Double
        let potentialProfit: Double?
        if let tp = takeProfit {
            let tpDistance = abs(tp - entryPrice)
            rr = stopDistance > 0 ? tpDistance / stopDistance : 0
            potentialProfit = recommended * (tpDistance / entryPrice)
        } else {
            rr = 0
            potentialProfit = nil
        }

        return PositionSizeResult(
            accountSize: accountSize,
            riskPercent: clampedRisk,
            riskAmount: riskAmount,
            stopLossPips: stopPips,
            positionSize: positionSize,
            pipValue: pipValue,
            maxPositionSize: maxPosition,
            recommendedStake: recommended,
            marginRequired: marginRequired,
            leverage: leverage,
            riskRewardRatio: rr,
            potentialProfit: potentialProfit,
            marginLevel: marginLevel
        )
    }

    /// Calculate comprehensive risk metrics for an account.
    func calculateRiskMetrics(accountSize: Double, winRate: Double = 0.5, avgRR: Double = 1.5) -> RiskMetricsResult {
        let maxDaily = accountSize * 0.02       // 2% max daily loss
        let maxWeekly = accountSize * 0.05      // 5% max weekly loss
        let maxPosition = accountSize * 0.01    // 1% max position risk

        // Kelly Criterion: f* = (p*b - q) / b
        let p = min(max(winRate, 0.01), 0.99)
        let q = 1 - p
        let b = max(avgRR, 0.1)
        let kelly = max(0, (p * b - q) / b)
        let halfKelly = kelly * 0.5

        // VaR approximation
        let dailyVol = accountSize * 0.01       // assumes 1% daily volatility
        let var95 = dailyVol * 1.645
        let cvar95 = dailyVol * 2.063

        // Suggested max consecutive losses to plan for
        let maxConsecutive = Int(ceil(log(0.01) / log(max(0.5, q))))

        // Stop trading limits
        let stopPct = (maxPosition / accountSize) * 100
        let dailyLimit = accountSize * 0.05     // 5% — stop trading for the day
        let weeklyLimit = accountSize * 0.10    // 10% — stop trading for the week

        return RiskMetricsResult(
            accountSize: accountSize,
            maxDailyLoss: maxDaily,
            maxWeeklyLoss: maxWeekly,
            maxPositionRisk: maxPosition,
            kellyFraction: kelly,
            halfKelly: halfKelly,
            var95: var95,
            cvar95: cvar95,
            maxConsecutiveLosses: maxConsecutive,
            suggestedStopLossPct: stopPct,
            dailyLossLimit: dailyLimit,
            weeklyLossLimit: weeklyLimit
        )
    }

    /// Calculate pip value for a given instrument and position size.
    func calculatePipValue(
        symbol: String,
        positionSize: Double,
        entryPrice: Double,
        isForex: Bool = false
    ) -> LotSizeInfo {
        let contractSize: Double
        if isForex || symbol.contains("/") {
            contractSize = 100_000      // standard forex lot
        } else {
            contractSize = 1            // synthetic indices
        }

        let standardLot = contractSize
        let miniLot = standardLot / 10
        let microLot = miniLot / 10
        let nanoLot = microLot / 10

        // Calculate position in lots
        let currentLotSize = contractSize > 0 ? positionSize / contractSize : 0

        // Pip value
        let pipValue = isForex ? (0.0001 / entryPrice) * positionSize : positionSize * 0.01

        let displayName = isForex ? "Forex" : "Synthetic"

        return LotSizeInfo(
            standardLot: standardLot,
            miniLot: miniLot,
            microLot: microLot,
            nanoLot: nanoLot,
            currentLotSize: currentLotSize,
            contractSize: contractSize,
            displayName: displayName
        )
    }

    /// Calculate potential profit/loss for a trade.
    func calculatePnL(
        entryPrice: Double,
        exitPrice: Double,
        positionSize: Double,
        direction: Direction,
        isForex: Bool = false
    ) -> (pnl: Double, pnlPercent: Double, pips: Double) {
        let multiplier = direction.isBullish ? 1.0 : -1.0
        let priceChange = (exitPrice - entryPrice) * multiplier
        let pnl = positionSize * (priceChange / entryPrice)

        let pnlPercent = positionSize > 0 ? (pnl / positionSize) * 100 : 0
        let pips = priceChange / (isForex ? 0.0001 : entryPrice * 0.0001)

        return (pnl, pnlPercent, pips)
    }

    /// Format a position calculator report for the chat tools.
    func formatReport(result: PositionSizeResult, symbol: String, direction: String) -> String {
        var report = "## 📐 Position Size Calculator\n\n"
        report += "**Trade:** \(direction.uppercased()) \(DerivSymbols.display(symbol))\n"
        report += "**Account:** \(fmt(result.accountSize)) | **Risk:** \(fmt(result.riskPercent))% = \(fmt(result.riskAmount))\n\n"

        report += "| Parameter | Value |\n|---|---|\n"
        report += "| Entry Price | \(fmt(result.recommendedStake > 0 ? result.recommendedStake / (result.accountSize * 0.01) * result.stopLossPips : 0)) |\n" // Placeholder
        report += "| Stop Loss (pips) | \(fmt(result.stopLossPips)) |\n"
        report += "| Recommended Stake | \(fmt(result.recommendedStake)) |\n"
        report += "| Pip Value | \(fmt(result.pipValue)) |\n"
        report += "| Margin Required | \(fmt(result.marginRequired)) |\n"
        report += "| Effective Leverage | \(fmt(result.leverage)):1 |\n"
        report += "| Margin Level | \(fmt(result.marginLevel))% |\n"

        if result.riskRewardRatio > 0 {
            report += "| Risk:Reward | 1:\(fmt(result.riskRewardRatio)) |\n"
            if let profit = result.potentialProfit {
                report += "| Potential Profit | \(fmt(profit)) |\n"
            }
        }

        report += "\n**Risk warnings:**\n"
        report += "- 📊 Never risk more than 1-2% per trade\n"
        report += "- 🛑 Aim for R:R of at least 1:2\n"
        report += "- 💡 Consider half-Kelly sizing: \(fmt(result.recommendedStake * 0.5))\n"

        return report
    }

    /// Format risk metrics report.
    func formatRiskReport(metrics: RiskMetricsResult) -> String {
        var report = "## 🛡️ Risk Management Profile\n\n"

        report += "| Metric | Value | Rule |\n|---|---|---|\n"
        report += "| Account Size | \(fmt(metrics.accountSize)) | |\n"
        report += "| Max Daily Loss | \(fmt(metrics.maxDailyLoss)) | 2% rule |\n"
        report += "| Max Weekly Loss | \(fmt(metrics.maxWeeklyLoss)) | 5% rule |\n"
        report += "| Max Per Trade Risk | \(fmt(metrics.maxPositionRisk)) | 1% rule |\n"
        report += "| Full Kelly | \(fmt(metrics.kellyFraction * 100))% | Optimal |\n"
        report += "| Half-Kelly | \(fmt(metrics.halfKelly * 100))% | Conservative |\n"
        report += "| 95% VaR (daily) | \(fmt(metrics.var95)) | 1-day risk |\n"
        report += "| 95% CVaR (daily) | \(fmt(metrics.cvar95)) | Tail risk |\n"
        report += "| Max Consecutive Losses | \(metrics.maxConsecutiveLosses) | Expected streak |\n"
        report += "| Daily Loss Limit | \(fmt(metrics.dailyLossLimit)) | Stop trading |\n"
        report += "| Weekly Loss Limit | \(fmt(metrics.weeklyLossLimit)) | Stop trading |\n"

        if metrics.kellyFraction > 0.25 {
            report += "\n⚠️ **High Kelly fraction** — consider using half-Kelly to reduce volatility.\n"
        }

        report += "\n**Risk rules to follow:**\n"
        report += "1. 🛑 If daily loss hits \(fmt(metrics.dailyLossLimit)), stop trading for the day\n"
        report += "2. 📉 If weekly loss hits \(fmt(metrics.weeklyLossLimit)), stop trading for the week\n"
        report += "3. 🎯 Never risk more than 1% on a single trade\n"
        report += "4. 📊 Track your actual win rate and R:R to refine Kelly estimates\n"

        return report
    }

    private func fmt(_ x: Double, _ places: Int = 2) -> String {
        x > 100 ? String(format: "%.\(places)f", x) : String(format: "%.\(places)f", x)
    }
}

// MARK: - Chat Tools for Position/Risk Calculator

extension ToolRegistry {
    /// Calculate position size from chat.
    func calculatePosition(args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let rawDirection = str(args, "direction").lowercased()
        let entryPrice = (args["entry"] as? Double) ?? Double(str(args, "entry")) ?? 0
        let stopLoss = (args["stop"] as? Double) ?? Double(str(args, "stop_loss")) ?? Double(str(args, "sl")) ?? 0
        let accountSize = (args["account"] as? Double) ?? Double(str(args, "account_size")) ?? Double(str(args, "balance")) ?? 10000
        let riskPercent = (args["risk"] as? Double) ?? Double(str(args, "risk_percent")) ?? 1.0
        let takeProfit = (args["take_profit"] as? Double) ?? Double(str(args, "tp")) ?? Double(str(args, "target"))
        let currency = str(args, "currency").isEmpty ? "USD" : str(args, "currency").uppercased()

        guard entryPrice > 0, stopLoss > 0, stopLoss != entryPrice else {
            return "Provide valid 'entry' and 'stop_loss' prices."
        }
        guard DerivSymbols.all.contains(symbol) else { return "Unknown symbol: '\(str(args, "symbol"))'. Use instruments() to see available symbols." }

        let isForex = symbol.contains("/") || currency != "USD"

        let result = PositionCalculatorService.shared.calculatePositionSize(
            accountSize: accountSize,
            riskPercent: riskPercent,
            entryPrice: entryPrice,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            currency: currency,
            isForex: isForex
        )

        let direction = rawDirection.contains("buy") || rawDirection.contains("long") ? "BUY" : "SELL"

        return PositionCalculatorService.shared.formatReport(result: result, symbol: symbol, direction: direction)
    }

    /// Calculate risk metrics from chat.
    func calculateRisk(args: [String: Any]) -> String {
        let accountSize = (args["account"] as? Double) ?? Double(str(args, "account_size")) ?? Double(str(args, "balance")) ?? 10000
        let winRate = (args["win_rate"] as? Double) ?? Double(str(args, "winrate")) ?? 0.5
        let avgRR = (args["rr"] as? Double) ?? Double(str(args, "avg_rr")) ?? Double(str(args, "reward_risk")) ?? 1.5

        let metrics = PositionCalculatorService.shared.calculateRiskMetrics(
            accountSize: accountSize,
            winRate: winRate,
            avgRR: avgRR
        )

        return PositionCalculatorService.shared.formatRiskReport(metrics: metrics)
    }

    /// Calculate pip value from chat.
    func calculatePips(args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let positionSize = (args["size"] as? Double) ?? Double(str(args, "position_size")) ?? Double(str(args, "stake")) ?? 100
        let entryPrice = (args["entry"] as? Double) ?? Double(str(args, "entry_price")) ?? Double(str(args, "price")) ?? 0

        guard entryPrice > 0 else { return "Provide a valid 'entry' price." }
        guard positionSize > 0 else { return "Provide a valid 'size' (position/stake)." }

        let isForex = symbol.contains("/")
        let info = PositionCalculatorService.shared.calculatePipValue(
            symbol: symbol,
            positionSize: positionSize,
            entryPrice: entryPrice,
            isForex: isForex
        )

        var report = "## 💧 Pip Value Calculator\n\n"
        report += "**Instrument:** \(DerivSymbols.display(symbol)) (\(info.displayName))\n"
        report += "**Position Size:** \(fmt(positionSize)) units (≈ \(fmt(info.currentLotSize * 100, 3))% of standard lot)\n\n"
        report += "| Unit | Size |\n|---|---|\n"
        report += "| Standard Lot | \(fmt(info.standardLot)) |\n"
        report += "| Mini Lot | \(fmt(info.miniLot)) |\n"
        report += "| Micro Lot | \(fmt(info.microLot)) |\n"
        report += "| Nano Lot | \(fmt(info.nanoLot)) |\n\n"
        report += "**Estimated Pip Value:** \(fmt(info.currentLotSize > 0 ? (positionSize * 0.01) : 0))\n"

        return report
    }

    /// Calculate potential P&L from chat.
    func calculatePnL(args: [String: Any]) -> String {
        let symbol = resolveSymbol(str(args, "symbol"))
        let entryPrice = (args["entry"] as? Double) ?? Double(str(args, "entry_price")) ?? 0
        let exitPrice = (args["exit"] as? Double) ?? Double(str(args, "exit_price")) ?? Double(str(args, "close")) ?? 0
        let positionSize = (args["size"] as? Double) ?? Double(str(args, "position_size")) ?? Double(str(args, "stake")) ?? 100
        let rawDirection = str(args, "direction").lowercased()

        guard entryPrice > 0, exitPrice > 0 else { return "Provide both 'entry' and 'exit' prices." }

        let direction: Direction = rawDirection.contains("buy") || rawDirection.contains("long") ? .bullish : .bearish
        let isForex = symbol.contains("/")

        let (pnl, pnlPercent, pips) = PositionCalculatorService.shared.calculatePnL(
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            positionSize: positionSize,
            direction: direction,
            isForex: isForex
        )

        var report = "## 📊 P&L Calculator\n\n"
        report += "**\(direction.isBullish ? "BUY" : "SELL")** \(DerivSymbols.display(symbol))\n"
        report += "Entry: \(fmt(entryPrice)) → Exit: \(fmt(exitPrice))\n\n"
        report += "| Metric | Value |\n|---|---|\n"
        report += "| P&L | \(pnl >= 0 ? "+" : "")\(fmt(pnl)) |\n"
        report += "| Return | \(pnlPercent >= 0 ? "+" : "")\(fmt(pnlPercent))% |\n"
        report += "| Pips | \(pips >= 0 ? "+" : "")\(fmt(pips)) |\n"
        report += "| Position Size | \(fmt(positionSize)) |\n"

        return report
    }

    private func fmt(_ x: Double, _ places: Int = 2) -> String {
        String(format: "%.\(places)f", x)
    }
}
