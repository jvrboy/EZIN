import Foundation

/// Container for all computed indicators (ported from TechnicalIndicators dataclass, extended).
struct TechnicalIndicators {
    // Core moving averages
    var sma20 = 0.0, sma50 = 0.0, sma200 = 0.0
    var ema12 = 0.0, ema26 = 0.0, ema50 = 0.0, ema200 = 0.0
    // Momentum
    var rsi14 = 50.0, rsi6 = 50.0
    var macdLine = 0.0, macdSignal = 0.0, macdHistogram = 0.0
    var stochK = 50.0, stochD = 50.0
    var cci20 = 0.0
    var williamsR = -50.0
    var momentum10 = 0.0, roc12 = 0.0, mfi14 = 50.0
    var trix = 0.0, ultimateOsc = 50.0, cmo = 0.0
    var ppoLine = 0.0, ppoSignal = 0.0, ppoHistogram = 0.0
    var fisherTransform = 0.0, priceZScore = 0.0, efficiencyRatio = 0.0
    // Volatility
    var bbUpper = 0.0, bbMiddle = 0.0, bbLower = 0.0, bbWidth = 0.0, bbPosition = 0.5
    var atr14 = 0.0, atr7 = 0.0
    var keltnerUpper = 0.0, keltnerMiddle = 0.0, keltnerLower = 0.0
    var donchianUpper = 0.0, donchianMiddle = 0.0, donchianLower = 0.0
    var stdDev = 0.0, historicalVol = 0.0, chaikinVol = 0.0, massIndex = 0.0, ulcerIndex = 0.0
    var atrPercent = 0.0, choppinessIndex = 50.0
    // Direction / trend
    var adx = 0.0, adxPlusDI = 0.0, adxMinusDI = 0.0
    var psar = 0.0
    var psarTrend = "neutral"
    var psarUp = true
    var supertrend = 0.0
    var supertrendUp = true
    var ichimokuTenkan = 0.0, ichimokuKijun = 0.0, ichimokuSenkouA = 0.0, ichimokuSenkouB = 0.0
    var gannUp = true
    var pivot = 0.0, pivotR1 = 0.0, pivotS1 = 0.0
    var hullFast = 0.0, hullSlow = 0.0
    var heikinBullish = true
    var linRegSlope = 0.0
    var aroonUp = 50.0, aroonDown = 50.0, aroonOscillator = 0.0
    var vortexPlus = 1.0, vortexMinus = 1.0
    var trendStrength = 0.0
    // Volume
    var obv = 0.0, vwma = 0.0
    var adLine = 0.0, cmf = 0.0, volumeOsc = 0.0, eom = 0.0, nvi = 0.0, pvi = 0.0, vwap = 0.0, forceIndex = 0.0
    var relativeVolume = 1.0
}
