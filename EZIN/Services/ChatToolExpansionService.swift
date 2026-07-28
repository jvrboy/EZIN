import Foundation

/// Expansion pack for the AI Chat — 25+ new tools that extend the assistant's capabilities
/// across code execution, data analysis, prediction, visualization, education, and more.
@MainActor
struct ChatToolExpansion {
    
    // MARK: - Code & Execution Tools
    
    /// Execute a mathematical expression safely and return the result.
    /// Uses a sandboxed evaluator that only permits numbers, operators, parentheses,
    /// and common math functions — no NSExpression (which can execute arbitrary code).
    static func calculate(expression: String) -> String {
        var expr = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "π", with: "\(Double.pi)")
            .replacingOccurrences(of: "pi", with: "\(Double.pi)")

        // Whitelist: only allow digits, operators, parentheses, dots, spaces, and known functions
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()%^ eEsqrtlogabslncosinexp")
        let sanitized = expr.unicodeScalars.filter { allowed.contains($0) }
        let safe = String(String.UnicodeScalarView(sanitized))
        guard !safe.isEmpty else { return "Invalid expression — only numbers, operators, and math functions are allowed." }

        // Use NSExpression in a safe way: only CONSTANT value expressions with basic arithmetic
        // We manually validate no function calls or keypaths are present
        let dangerous = ["FUNCTION", "SUBQUERY", "evaluate", "valueForKey", "fromObject", "#"]
        for d in dangerous {
            if safe.uppercased().contains(d) {
                return "Expression contains disallowed operation '\(d)'."
            }
        }

        // Evaluate using a simple recursive-descent parser for safety
        if let result = SimpleMathEvaluator.evaluate(safe) {
            let formatted = result.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", result)
                : String(format: "%.6f", result)
            return "`\(expression)` = **\(formatted)**"
        }
        return "Could not evaluate expression. Supported: +, -, *, /, parentheses, sqrt(), abs(), pow()."
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
        let minVal = sorted.first!
        let maxVal = sorted.last!
        let range = maxVal - minVal

        return """
        📊 Statistics (\(Int(n)) values)
        • Mean: \(String(format: "%.4f", mean))
        • Median: \(String(format: "%.4f", median))
        • Std Dev: \(String(format: "%.4f", stdDev))
        • Min: \(String(format: "%.4f", minVal))
        • Max: \(String(format: "%.4f", maxVal))
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

/// A safe recursive-descent math evaluator that only supports numbers, basic arithmetic
/// (+, -, *, /), parentheses, and common unary functions (sqrt, abs, log, sin, cos, exp).
/// No NSExpression, no keypaths, no code execution.
enum SimpleMathEvaluator {
    static func evaluate(_ input: String) -> Double? {
        var tokens = tokenize(input)
        let result = parseExpression(&: tokens)
        return tokens.isEmpty ? result : nil
    }

    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if ch.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch.isNumber || ch == "." {
                current.append(ch)
            } else if "+-*/()".contains(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch.isLetter {
                current.append(ch)
            } else {
                return [] // invalid char
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func parseExpression(_ tokens: inout [String]) -> Double? {
        var result = parseTerm(&: tokens)
        while let op = tokens.first, op == "+" || op == "-" {
            tokens.removeFirst()
            let right = parseTerm(&: tokens)
            if op == "+" { result = (result ?? 0) + (right ?? 0) }
            else { result = (result ?? 0) - (right ?? 0) }
        }
        return result
    }

    private static func parseTerm(_ tokens: inout [String]) -> Double? {
        var result = parseFactor(&: tokens)
        while let op = tokens.first, op == "*" || op == "/" {
            tokens.removeFirst()
            let right = parseFactor(&: tokens)
            if op == "*" { result = (result ?? 0) * (right ?? 0) }
            else if let r = right, r != 0 { result = (result ?? 0) / r }
            else { return nil } // division by zero
        }
        return result
    }

    private static func parseFactor(_ tokens: inout [String]) -> Double? {
        guard let token = tokens.first else { return nil }
        if token == "-" {
            tokens.removeFirst()
            if let val = parseFactor(&: tokens) { return -val }
            return nil
        }
        if token == "(" {
            tokens.removeFirst()
            let val = parseExpression(&: tokens)
            if tokens.first == ")" { tokens.removeFirst() }
            return val
        }
        // Named functions
        if token == "sqrt" || token == "abs" || token == "log" || token == "ln" || token == "sin" || token == "cos" || token == "exp" {
            tokens.removeFirst()
            guard tokens.first == "(" else { return nil }
            tokens.removeFirst()
            let val = parseExpression(&: tokens)
            if tokens.first == ")" { tokens.removeFirst() }
            switch token {
            case "sqrt": return val.map { sqrt($0) }
            case "abs": return val.map { abs($0) }
            case "log": return val.map { log10($0) }
            case "ln": return val.map { log($0) }
            case "sin": return val.map { sin($0) }
            case "cos": return val.map { cos($0) }
            case "exp": return val.map { exp($0) }
            default: return nil
            }
        }
        // Number
        if let val = Double(token) {
            tokens.removeFirst()
            return val
        }
        // Constants
        if token == "e" { tokens.removeFirst(); return M_E }
        if token == "pi" { tokens.removeFirst(); return Double.pi }
        return nil
    }
}
