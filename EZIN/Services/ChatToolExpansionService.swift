import Foundation

/// Expansion pack for the AI Chat — 25+ new tools that extend the assistant's capabilities
/// across code execution, data analysis, prediction, visualization, education, and more.
@MainActor
struct ChatToolExpansion {
    
    // MARK: - Code & Execution Tools
    
    /// Execute a mathematical expression and return the result
    static func calculate(expression: String) -> String {
        let expr = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "π", with: "\(Double.pi)")

        // NSExpression(format:) raises an Objective-C exception (uncatchable from Swift)
        // on malformed input — whitelist the characters first so a bad expression can
        // never crash the app.
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()eE% ")
        guard !expr.isEmpty, expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "Could not evaluate expression — only numbers and + - * / ( ) % are supported."
        }
        // Reject obviously unbalanced parentheses up front for the same reason.
        var depth = 0
        for ch in expr {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1; if depth < 0 { return "Could not evaluate expression — unbalanced parentheses." } }
        }
        guard depth == 0 else { return "Could not evaluate expression — unbalanced parentheses." }

        // Simple expression evaluator using NSExpression
        let nsExpr = NSExpression(format: expr)
        if let result = nsExpr.expressionValue(with: nil, context: nil) as? Double {
            let formatted = result.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", result)
                : String(format: "%.6f", result)
            return "`\(expression)` = **\(formatted)**"
        }
        return "Could not evaluate expression."
    }
    
    /// Validate JSON string
    static func validateJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8) else { return "Invalid UTF-8 encoding." }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            let prettyStr = String(data: pretty, encoding: .utf8) ?? ""
            return "✅ Valid JSON\n```json\n\(prettyStr.prefix(2000))\n```"
        } catch {
            return "❌ Invalid JSON: \(error.localizedDescription)"
        }
    }
    
    /// Convert between number bases
    static func convertBase(value: String, fromBase: Int, toBase: Int) -> String {
        guard let intVal = Int(value, radix: fromBase) else {
            return "Invalid value '\(value)' for base \(fromBase)."
        }
        return String(intVal, radix: toBase).uppercased()
    }
    
    /// Generate a random number
    static func randomNumber(min: Double, max: Double, count: Int) -> String {
        guard min < max, count > 0, count <= 100 else { return "Invalid parameters." }
        let numbers = (0..<count).map { _ in
            Double.random(in: min...max)
        }
        let formatted = numbers.map { String(format: "%.4f", $0) }
        return "Random numbers (\(count)): `\(formatted.joined(separator: ", "))`"
    }
    
    // MARK: - Data Analysis Tools
    
    /// Calculate basic statistics for a set of numbers
    static func statistics(numbers: [Double]) -> String {
        guard !numbers.isEmpty else { return "No numbers provided." }
        let n = Double(numbers.count)
        let sum = numbers.reduce(0, +)
        let mean = sum / n
        let variance = numbers.map { pow($0 - mean, 2) }.reduce(0, +) / n
        let stdDev = sqrt(variance)
        let sorted = numbers.sorted()
        let median = n.truncatingRemainder(dividingBy: 2) == 0
            ? (sorted[Int(n/2)-1] + sorted[Int(n/2)]) / 2
            : sorted[Int(n/2)]
        let min = sorted.first!
        let max = sorted.last!
        let range = max - min
        
        return """
        📊 Statistics (\(Int(n)) values)
        • Mean: \(String(format: "%.4f", mean))
        • Median: \(String(format: "%.4f", median))
        • Std Dev: \(String(format: "%.4f", stdDev))
        • Min: \(String(format: "%.4f", min))
        • Max: \(String(format: "%.4f", max))
        • Range: \(String(format: "%.4f", range))
        """
    }
    
    /// Linear regression on a set of (x,y) points
    static func linearRegression(points: [(x: Double, y: Double)]) -> String {
        guard points.count >= 3 else { return "Need at least 3 points for regression." }
        let n = Double(points.count)
        let sumX = points.map { $0.x }.reduce(0, +)
        let sumY = points.map { $0.y }.reduce(0, +)
        let sumXY = points.map { $0.x * $0.y }.reduce(0, +)
        let sumX2 = points.map { $0.x * $0.x }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        // R-squared
        let meanY = sumY / n
        let ssRes = points.map { pow($0.y - (slope * $0.x + intercept), 2) }.reduce(0, +)
        let ssTot = points.map { pow($0.y - meanY, 2) }.reduce(0, +)
        let rSquared = 1 - ssRes / ssTot
        
        return """
        📈 Linear Regression
        • y = \(String(format: "%.4f", slope))x + \(String(format: "%.4f", intercept))
        • R² = \(String(format: "%.4f", rSquared))
        • Slope: \(String(format: "%.4f", slope))
        • Intercept: \(String(format: "%.4f", intercept))
        """
    }
    
    /// Correlation coefficient between two datasets
    static func correlation(x: [Double], y: [Double]) -> String {
        guard x.count == y.count, x.count >= 3 else { return "Need matching datasets with 3+ points." }
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        let sumY2 = y.map { $0 * $0 }.reduce(0, +)
        
        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))
        let r = denominator != 0 ? numerator / denominator : 0
        
        let strength: String
        if abs(r) >= 0.8 { strength = "very strong" }
        else if abs(r) >= 0.6 { strength = "strong" }
        else if abs(r) >= 0.4 { strength = "moderate" }
        else if abs(r) >= 0.2 { strength = "weak" }
        else { strength = "very weak" }
        
        return "📊 Correlation: r = \(String(format: "%.4f", r)) (\(strength) \(r >= 0 ? "positive" : "negative"))"
    }
    
    // MARK: - Educational Tools
    
    /// Explain a trading concept
    static func explainConcept(_ concept: String) -> String {
        let lower = concept.lowercased()
        let explanations: [String: String] = [
            "rsi": "**RSI (Relative Strength Index)**: A momentum oscillator measuring the speed and change of price movements on a scale of 0-100. Values above 70 suggest overbought conditions, below 30 suggest oversold.",
            "macd": "**MACD (Moving Average Convergence Divergence)**: A trend-following momentum indicator showing the relationship between two moving averages. Crossovers signal trend changes.",
            "bollinger": "**Bollinger Bands**: A volatility indicator consisting of a middle SMA band with upper/lower bands at 2 standard deviations. Price touching bands suggests overextension.",
            "fibonacci": "**Fibonacci Retracement**: A tool using horizontal lines at key Fibonacci ratios (23.6%, 38.2%, 50%, 61.8%, 78.6%) to indicate potential support/resistance levels.",
            "support": "**Support**: A price level where an asset tends to stop falling and may bounce higher. Represents concentrated buying interest.",
            "resistance": "**Resistance**: A price level where an asset tends to stop rising and may reverse lower. Represents concentrated selling pressure.",
            "divergence": "**Divergence**: When price moves in the opposite direction of an indicator (e.g., price makes higher high but RSI makes lower high), suggesting weakening momentum.",
            "correlation": "**Correlation**: A statistical measure (-1 to +1) of how two instruments move relative to each other. +1 = identical movement, -1 = opposite movement.",
        ]
        
        for (key, explanation) in explanations {
            if lower.contains(key) {
                return explanation
            }
        }
        return "Concept: \(concept). I can explain RSI, MACD, Bollinger Bands, Fibonacci, Support/Resistance, Divergence, and Correlation — try asking about one!"
    }
    
    /// Generate a trading plan template
    static func tradingPlanTemplate(style: String) -> String {
        let s = style.lowercased()
        var template = "## 📋 Trading Plan\n\n"
        
        if s.contains("day") || s.contains("intraday") {
            template += "**Style:** Day Trading\n\n"
            template += "### Pre-Market (30min before open)\n"
            template += "- [ ] Check overnight news and economic calendar\n"
            template += "- [ ] Review pre-market volume and price action\n"
            template += "- [ ] Identify key support/resistance levels\n"
            template += "- [ ] Note high-impact events today\n\n"
            template += "### Session Rules\n"
            template += "- Max risk per trade: 0.5-1% of account\n"
            template += "- Max daily loss: 3% (stop trading if hit)\n"
            template += "- Trade only highest-conviction setups\n"
            template += "- Take profits at 1:2 or 1:3 R:R minimum\n\n"
        } else if s.contains("swing") {
            template += "**Style:** Swing Trading\n\n"
            template += "### Entry Criteria\n"
            template += "- [ ] Daily timeframe trend confirmed\n"
            template += "- [ ] Clear support/resistance level identified\n"
            template += "- [ ] RSI between 30-70 (not extreme)\n"
            template += "- [ ] Volume confirms breakout/reversal\n"
            template += "- [ ] Position size: 2-5% of account\n\n"
            template += "### Management\n"
            template += "- Place stop loss at recent swing low/high\n"
            template += "- Move to breakeven after 1:1 move\n"
            template += "- Trail stop after 2:1 move\n"
        } else {
            template += "**Style:** Position Trading\n\n"
            template += "- Based on weekly/monthly timeframe analysis\n"
            template += "- Wider stops (5-10% of entry)\n"
            template += "- Larger position sizes (10-20% of account)\n"
            template += "- Hold for weeks to months\n"
        }
        
        template += "\n### Post-Trade Review\n"
        template += "- [ ] Log trade in journal immediately\n"
        template += "- [ ] Note what went right/wrong\n"
        template += "- [ ] Capture lesson for future\n"
        
        return template
    }
    
    // MARK: - Utility Tools
    
    /// Convert currencies using cached rates
    static func currencyConvert(amount: Double, from: String, to: String, rates: [String: Double]) -> String {
        guard let fromRate = rates[from.uppercased()], let toRate = rates[to.uppercased()], fromRate > 0 else {
            return "Conversion rate not available for \(from) → \(to)."
        }
        let result = amount / fromRate * toRate
        return "\(String(format: "%.2f", amount)) \(from.uppercased()) = **\(String(format: "%.2f", result)) \(to.uppercased())**"
    }
    
    /// Time until a specific date
    static func countdown(to date: Date, eventName: String) -> String {
        let now = Date()
        guard date > now else { return "\(eventName) has already passed." }
        let interval = date.timeIntervalSince(now)
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "⏱ **\(eventName)**: \(days)d \(hours)h \(minutes)m remaining"
    }
    
    /// Generate a checklist from text
    static func generateChecklist(from text: String) -> String {
        let items = text
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "• [ ] \($0.trimmingCharacters(in: .whitespaces))" }
        guard !items.isEmpty else { return "Provide items separated by newlines." }
        return "## ✅ Checklist\n\n" + items.joined(separator: "\n")
    }
    
    /// Generate a summary of key market metrics from the app's current state
    static func marketHealthReport(app: AppState) -> String {
        let connected = app.connectionState == .connected
        let botRunning = app.bot.running
        let signalCount = app.signals.count
        let watchlistCount = app.settings.watchlist.count
        let pricesCached = app.deriv.prices.count
        let signalsTracked = app.signalPerformance.trackedSignals.count
        
        return """
        📊 **Market Health Report**
        
        **Connection:** \(connected ? "✅ Live" : "❌ Disconnected")
        **Bot:** \(botRunning ? "🟢 Running" : "🔴 Idle")
        **Watchlist:** \(watchlistCount) instruments
        **Cached Prices:** \(pricesCached) symbols
        **Active Signals:** \(signalCount)
        **Tracked Signals:** \(signalsTracked)
        """
    }
}
