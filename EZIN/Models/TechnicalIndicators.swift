import Foundation

/// Container for all computed indicators (ported from TechnicalIndicators dataclass).
struct TechnicalIndicators {
    var sma20 = 0.0, sma50 = 0.0, sma200 = 0.0
    var ema12 = 0.0, ema26 = 0.0, ema50 = 0.0, ema200 = 0.0
    var rsi14 = 50.0, rsi6 = 50.0
    var macdLine = 0.0, macdSignal = 0.0, macdHistogram = 0.0
    var bbUpper = 0.0, bbMiddle = 0.0, bbLower = 0.0, bbWidth = 0.0, bbPosition = 0.5
    var atr14 = 0.0, atr7 = 0.0
    var stochK = 50.0, stochD = 50.0
    var adx = 0.0, adxPlusDI = 0.0, adxMinusDI = 0.0
    var obv = 0.0, vwma = 0.0
    var cci20 = 0.0
    var williamsR = -50.0
    var momentum10 = 0.0, roc12 = 0.0, mfi14 = 50.0
    var psar = 0.0
    var psarTrend = "neutral"
    var supertrend = 0.0
    var supertrendUp = true
}
