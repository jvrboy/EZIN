import Foundation

/// Expanded bot strategy library with 8 new trading strategies

// MARK: - Bot Strategy Protocol (file-scope for Swift 5 compat)

protocol BotStrategy {
    var name: String { get }
    var description: String { get }
    var botRiskLevel: BotRiskLevel { get }
    var timeframes: [Timeframe] { get }
    var defaultParameters: [String: Double] { get }
    func shouldEnter(data: StrategyInput) -> (Bool, Double, String)
    func shouldExit(data: StrategyInput) -> (Bool, String)
}

enum BotRiskLevel: String, Codable, CaseIterable {
    case veryLow = "Very Low"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very High"

    var maxRiskPerTrade: Double {
        switch self {
        case .veryLow: return 0.002
        case .low: return 0.005
        case .medium: return 0.01
        case .high: return 0.02
        case .veryHigh: return 0.05
        }
    }
}

struct StrategyInput {
    let symbol: String
    let timeframe: Timeframe
    let candles: [Candle]
    let currentPrice: Double
    let indicators: IndicatorValues
    let regime: String?
}

struct IndicatorValues {
    let rsi: [Double]
    let macdLine: [Double]
    let macdSignal: [Double]
    let macdHistogram: [Double]
    let bbUpper: [Double]
    let bbLower: [Double]
    let bbMiddle: [Double]
    let atr: [Double]
    let smaFast: [Double]
    let smaSlow: [Double]
    let volume: [Double]

    var latestRSI: Double { rsi.last ?? 50 }
    var latestATR: Double { atr.last ?? 0 }
}

struct BotStrategyLibrary {
    
    // MARK: - Strategy Implementations
    
    /// 1. Mean Reversion on RSI extremes
    struct RSIMeanReversion: BotStrategy {
        let name = "RSI Mean Reversion"
        let description = "Buys when RSI < 30 (oversold), sells when RSI > 70 (overbought)"
        let botRiskLevel: BotRiskLevel = .medium
        let timeframes: [Timeframe] = [.m5, .m15, .m30, .h1]
        let defaultParameters: [String: Double] = ["rsiPeriod": 14, "oversold": 30, "overbought": 70, "lookback": 3]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            let rsi = data.indicators.latestRSI
            let oversold = defaultParameters["oversold"] ?? 30
            let overbought = defaultParameters["overbought"] ?? 70
            let lookback = Int(defaultParameters["lookback"] ?? 3)
            
            guard data.indicators.rsi.count > lookback else { return (false, 0, "Insufficient data") }
            
            let prevRSI = data.indicators.rsi[data.indicators.rsi.count - lookback]
            
            // Bullish: RSI was oversold now recovering
            if prevRSI <= oversold && rsi > oversold {
                return (true, 0.65, "RSI recovering from oversold (\(String(format: "%.1f", prevRSI)) → \(String(format: "%.1f", rsi)))")
            }
            
            // Bearish: RSI was overbought now declining
            if prevRSI >= overbought && rsi < overbought {
                return (true, 0.6, "RSI declining from overbought (\(String(format: "%.1f", prevRSI)) → \(String(format: "%.1f", rsi)))")
            }
            
            return (false, 0, "No clear RSI extreme")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            let rsi = data.indicators.latestRSI
            if rsi > 50 && data.currentPrice > 0 { return (true, "RSI returned to neutral") }
            if rsi < 50 && data.currentPrice > 0 { return (true, "RSI returned to neutral") }
            return (false, "Holding")
        }
    }
    
    /// 2. MACD Crossover Momentum
    struct MACDMomentum: BotStrategy {
        let name = "MACD Momentum"
        let description = "Follows MACD line/signal crossovers for trend momentum"
        let botRiskLevel: BotRiskLevel = .medium
        let timeframes: [Timeframe] = [.m15, .m30, .h1, .h4]
        let defaultParameters: [String: Double] = ["fast": 12, "slow": 26, "signal": 9]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            guard data.indicators.macdLine.count >= 2, data.indicators.macdSignal.count >= 2 else {
                return (false, 0, "Insufficient MACD data")
            }
            
            let currMacd = data.indicators.macdLine.last!
            let currSig = data.indicators.macdSignal.last!
            let prevMacd = data.indicators.macdLine[data.indicators.macdLine.count - 2]
            let prevSig = data.indicators.macdSignal[data.indicators.macdSignal.count - 2]
            
            // Bullish crossover
            if prevMacd <= prevSig && currMacd > currSig {
                let strength = currMacd > 0 ? 0.7 : 0.6
                return (true, strength, "MACD bullish crossover (histogram: \(String(format: "%.4f", data.indicators.macdHistogram.last ?? 0)))")
            }
            
            // Bearish crossover
            if prevMacd >= prevSig && currMacd < currSig {
                let strength = currMacd < 0 ? 0.7 : 0.6
                return (true, strength, "MACD bearish crossover")
            }
            
            return (false, 0, "No MACD crossover")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            guard data.indicators.macdLine.count >= 2, data.indicators.macdSignal.count >= 2 else {
                return (false, "Holding")
            }
            
            let currMacd = data.indicators.macdLine.last!
            let currSig = data.indicators.macdSignal.last!
            
            // Exit on opposite crossover
            if currMacd < currSig { return (true, "MACD bearish crossover signal") }
            return (false, "Momentum continues")
        }
    }
    
    /// 3. Bollinger Band Squeeze Breakout
    struct BollingerSqueeze: BotStrategy {
        let name = "Bollinger Squeeze"
        let description = "Trades breakouts from low-volatility Bollinger Band squeezes"
        let botRiskLevel: BotRiskLevel = .high
        let timeframes: [Timeframe] = [.m5, .m15, .h1]
        let defaultParameters: [String: Double] = ["bbPeriod": 20, "bbStdDev": 2.0, "squeezeThreshold": 0.1]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            guard data.indicators.bbUpper.count >= 5 else { return (false, 0, "Insufficient BB data") }
            
            let upper = data.indicators.bbUpper
            let lower = data.indicators.bbLower
            let recent = 5
            let lastIdx = upper.count - 1
            
            // Calculate band width over recent periods
            let currentWidth = (upper[lastIdx] - lower[lastIdx]) / data.currentPrice
            let avgWidth = (0..<recent).map { i in
                (upper[lastIdx - i] - lower[lastIdx - i]) / data.currentPrice
            }.reduce(0, +) / Double(recent)
            
            guard currentWidth < avgWidth * 1.1 else { return (false, 0, "No squeeze detected") }
            
            // Breakout direction
            if data.currentPrice > upper[lastIdx] {
                return (true, 0.7, "Bullish breakout from Bollinger squeeze")
            }
            if data.currentPrice < lower[lastIdx] {
                return (true, 0.65, "Bearish breakdown from Bollinger squeeze")
            }
            
            return (false, 0, "No breakout yet")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            let width = (data.indicators.bbUpper.last! - data.indicators.bbLower.last!) / data.currentPrice
            if width > 0.05 { return (true, "Band widening - momentum exhausting") }
            return (false, "Riding breakout")
        }
    }
    
    /// 4. Trend Following with 2 Moving Averages
    struct TrendFollower: BotStrategy {
        let name = "Trend Follower"
        let description = "Follows trend using SMA fast/slow crossover on higher timeframes"
        let botRiskLevel: BotRiskLevel = .medium
        let timeframes: [Timeframe] = [.h1, .h4, .d1]
        let defaultParameters: [String: Double] = ["fastMA": 20, "slowMA": 50, "trendStrength": 0.6]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            guard data.indicators.smaFast.count >= 2, data.indicators.smaSlow.count >= 2 else {
                return (false, 0, "Insufficient MA data")
            }
            
            let fast = data.indicators.smaFast.last!
            let slow = data.indicators.smaSlow.last!
            let price = data.currentPrice
            
            if fast > slow && price > fast {
                return (true, 0.7, "Uptrend: price(\(String(format: "%.2f", price))) > fast(\(String(format: "%.2f", fast))) > slow(\(String(format: "%.2f", slow)))")
            }
            if fast < slow && price < fast {
                return (true, 0.65, "Downtrend detected")
            }
            
            return (false, 0, "No clear trend")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            guard data.indicators.smaFast.count >= 2, data.indicators.smaSlow.count >= 2 else {
                return (false, "Holding")
            }
            let fast = data.indicators.smaFast.last!
            let slow = data.indicators.smaSlow.last!
            if abs(fast - slow) / slow < 0.001 { return (true, "MA convergence - trend weakening") }
            return (false, "Trend intact")
        }
    }
    
    /// 5. Volume Spike Breakout
    struct VolumeSpike: BotStrategy {
        let name = "Volume Spike"
        let description = "Detects abnormal volume spikes as breakout confirmation"
        let riskLevel: RiskLevel = .high
        let timeframes: [Timeframe] = [.m5, .m15]
        let defaultParameters: [String: Double] = ["volumeMultiplier": 2.0, "lookback": 20]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            guard data.indicators.volume.count >= 3 else { return (false, 0, "Insufficient volume data") }
            
            let vol = data.indicators.volume
            let lookback = min(Int(defaultParameters["lookback"] ?? 20), vol.count - 1)
            let multiplier = defaultParameters["volumeMultiplier"] ?? 2.0
            
            let avgVol = vol.suffix(lookback).dropLast().reduce(0, +) / Double(lookback)
            let currentVol = vol.last!
            
            guard currentVol > avgVol * multiplier else { return (false, 0, "No volume spike") }
            
            let direction = data.currentPrice > (data.indicators.smaFast.last ?? data.currentPrice) ? "bullish" : "bearish"
            let ratio = currentVol / avgVol
            return (true, min(0.75, ratio * 0.15), "Volume spike: \(String(format: "%.1f", ratio))x average (\(direction))")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            let vol = data.indicators.volume.last ?? 0
            let avg = data.indicators.volume.suffix(10).dropLast().reduce(0, +) / 9
            if vol < avg * 0.5 { return (true, "Volume drying up") }
            return (false, "Volume sustained")
        }
    }
    
    /// 6. ATR Breakout / Volatility Expansion
    struct ATRBreakout: BotStrategy {
        let name = "ATR Breakout"
        let description = "Trades breakouts beyond ATR-based volatility envelopes"
        let botRiskLevel: BotRiskLevel = .veryHigh
        let timeframes: [Timeframe] = [.m5, .m15, .h1]
        let defaultParameters: [String: Double] = ["atrPeriod": 14, "atrMultiplier": 1.5, "lookback": 10]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            guard data.indicators.atr.count >= 2, data.indicators.smaFast.count >= 1 else {
                return (false, 0, "Insufficient ATR data")
            }
            
            let atr = data.indicators.atr.last!
            let sma = data.indicators.smaFast.last!
            let price = data.currentPrice
            let multiplier = defaultParameters["atrMultiplier"] ?? 1.5
            
            if price > sma + atr * multiplier {
                return (true, 0.75, "Bullish ATR breakout: price \(String(format: "%.2f", price)) > \(String(format: "%.2f", sma)) + \(String(format: "%.2f", atr * multiplier))")
            }
            if price < sma - atr * multiplier {
                return (true, 0.7, "Bearish ATR breakdown")
            }
            
            return (false, 0, "No ATR breakout")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            let atr = data.indicators.atr.last ?? 0
            if data.currentPrice < (data.indicators.smaFast.last ?? 0) - atr * 0.5 {
                return (true, "Price retraced significantly")
            }
            return (false, "Momentum continues")
        }
    }
    
    /// 7. Support/Resistance Bounce
    struct SRBounce: BotStrategy {
        let name = "S/R Bounce"
        let description = "Buys at support levels, sells at resistance with confirmation"
        let botRiskLevel: BotRiskLevel = .medium
        let timeframes: [Timeframe] = [.m15, .m30, .h1, .h4]
        let defaultParameters: [String: Double] = ["bounceThreshold": 0.005, "confirmationBars": 2]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            let prices = data.candles.map { $0.close }
            let recent = prices.suffix(20)
            
            // Basic S/R detection: recent lows/highs
            let lows = (1..<recent.count - 1).filter { i in
                recent[recent.index(recent.startIndex, offsetBy: i)] <
                recent[recent.index(recent.startIndex, offsetBy: i - 1)] &&
                recent[recent.index(recent.startIndex, offsetBy: i)] <
                recent[recent.index(recent.startIndex, offsetBy: i + 1)]
            }.map { recent[recent.index(recent.startIndex, offsetBy: $0)] }
            
            let highs = (1..<recent.count - 1).filter { i in
                recent[recent.index(recent.startIndex, offsetBy: i)] >
                recent[recent.index(recent.startIndex, offsetBy: i - 1)] &&
                recent[recent.index(recent.startIndex, offsetBy: i)] >
                recent[recent.index(recent.startIndex, offsetBy: i + 1)]
            }.map { recent[recent.index(recent.startIndex, offsetBy: $0)] }
            
            guard !lows.isEmpty, !highs.isEmpty else { return (false, 0, "No clear S/R levels") }
            
            let nearestSupport = lows.max() ?? 0
            let nearestResistance = highs.min() ?? Double.greatestFiniteMagnitude
            let threshold = (defaultParameters["bounceThreshold"] ?? 0.005) * data.currentPrice
            
            if data.currentPrice > nearestSupport && data.currentPrice < nearestSupport + threshold {
                return (true, 0.6, "Bouncing from support at \(String(format: "%.2f", nearestSupport))")
            }
            if data.currentPrice < nearestResistance && data.currentPrice > nearestResistance - threshold {
                return (true, 0.55, "Rejecting from resistance at \(String(format: "%.2f", nearestResistance))")
            }
            
            return (false, 0, "No S/R bounce")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            let prices = data.candles.map { $0.close }
            let recent = prices.suffix(3)
            guard recent.count == 3 else { return (false, "Holding") }
            if recent[recent.index(before: recent.endIndex)] < recent[recent.startIndex] {
                return (true, "Price reversing from bounce")
            }
            return (false, "Bounce continuing")
        }
    }
    
    /// 8. Multi-Timeframe Confluence
    struct MTFConfluence: BotStrategy {
        let name = "MTF Confluence"
        let description = "Requires confluence across 3 timeframes before entering"
        let botRiskLevel: BotRiskLevel = .veryLow
        let timeframes: [Timeframe] = [.m15, .h1, .h4, .d1]
        let defaultParameters: [String: Double] = ["minTimeframes": 3, "minConfidence": 0.6]
        
        func shouldEnter(data: StrategyInput) -> (Bool, Double, String) {
            // Multi-timeframe confluence requires checking multiple timeframes
            // Simplified: use ATR trend strength as proxy
            let smaFast = data.indicators.smaFast.last ?? data.currentPrice
            let smaSlow = data.indicators.smaSlow.last ?? data.currentPrice
            
            let trendUp = smaFast > smaSlow && data.currentPrice > smaFast
            let trendDown = smaFast < smaSlow && data.currentPrice < smaFast
            
            let rsi = data.indicators.latestRSI
            let rsiConfirms = (trendUp && rsi > 50) || (trendDown && rsi < 50)
            
            if trendUp && rsiConfirms {
                return (true, 0.8, "Bullish confluence: MA trend up + RSI \(String(format: "%.1f", rsi)) confirms")
            }
            if trendDown && rsiConfirms {
                return (true, 0.75, "Bearish confluence detected")
            }
            
            return (false, 0, "Insufficient confluence")
        }
        
        func shouldExit(data: StrategyInput) -> (Bool, String) {
            let smaFast = data.indicators.smaFast.last ?? data.currentPrice
            let smaSlow = data.indicators.smaSlow.last ?? data.currentPrice
            if abs(smaFast - smaSlow) / smaSlow < 0.0005 {
                return (true, "MA convergence - trend reversal risk")
            }
            return (false, "Confluence holding")
        }
    }
    
    // MARK: - Strategy Registry
    
    static let allStrategies: [any BotStrategy] = [
        RSIMeanReversion(),
        MACDMomentum(),
        BollingerSqueeze(),
        TrendFollower(),
        VolumeSpike(),
        ATRBreakout(),
        SRBounce(),
        MTFConfluence()
    ]
    
    static func strategy(named name: String) -> (any BotStrategy)? {
        allStrategies.first { $0.name.lowercased() == name.lowercased() }
    }
    
    static func strategies(for timeframe: Timeframe) -> [any BotStrategy] {
        allStrategies.filter { $0.timeframes.contains(timeframe) }
    }
    
    static func strategies(riskLevel botRiskLevel: BotRiskLevel) -> [any BotStrategy] {
        allStrategies.filter { $0.riskLevel == riskLevel }
    }
    
    static func catalog() -> String {
        var result = "## 📚 Bot Strategy Library\n\n"
        for strategy in allStrategies {
            result += "### \(strategy.name)\n"
            result += "\(strategy.description)\n"
            result += "Risk: \(strategy.riskLevel.rawValue) · Timeframes: \(strategy.timeframes.map { $0.rawValue }.joined(separator: ", "))\n\n"
        }
        return result
    }
}
