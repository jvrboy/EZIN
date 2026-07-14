import Foundation

/// Computes the full TechnicalIndicators snapshot from market data
/// (port of analysis.indicators.TechnicalAnalyzer.analyze, extended with new studies).
struct TechnicalAnalyzer {
    func analyze(_ md: MarketData) -> TechnicalIndicators {
        var t = TechnicalIndicators()
        let close = md.closes, high = md.highs, low = md.lows, vol = md.volumes
        guard close.count > 2 else { return t }

        func last(_ a: [Double]) -> Double { a.last ?? 0 }

        t.sma20 = last(MA.sma(close, 20))
        t.sma50 = last(MA.sma(close, 50))
        t.sma200 = last(MA.sma(close, 200))
        t.ema12 = last(MA.ema(close, 12))
        t.ema26 = last(MA.ema(close, 26))
        t.ema50 = last(MA.ema(close, 50))
        t.ema200 = last(MA.ema(close, 200))

        t.rsi14 = last(Indicators.rsi(close, 14))
        t.rsi6 = last(Indicators.rsi(close, 6))

        let m = Indicators.macd(close)
        t.macdLine = last(m.macd); t.macdSignal = last(m.signal); t.macdHistogram = last(m.histogram)

        let bb = Indicators.bollinger(close)
        t.bbUpper = last(bb.upper); t.bbMiddle = last(bb.middle); t.bbLower = last(bb.lower)
        t.bbWidth = t.bbMiddle != 0 ? (t.bbUpper - t.bbLower) / t.bbMiddle : 0
        let denom = (t.bbUpper - t.bbLower)
        t.bbPosition = denom != 0 ? (last(close) - t.bbLower) / denom : 0.5

        t.atr14 = last(Indicators.atr(high, low, close, 14))
        t.atr7 = last(Indicators.atr(high, low, close, 7))
        t.atrPercent = last(close) != 0 ? t.atr14 / abs(last(close)) * 100 : 0

        let st = Indicators.stochastic(high, low, close)
        t.stochK = last(st.k); t.stochD = last(st.d)

        let a = Indicators.adx(high, low, close)
        t.adx = last(a.adx); t.adxPlusDI = last(a.plusDI); t.adxMinusDI = last(a.minusDI)

        t.obv = last(Indicators.obv(close, vol))
        t.cci20 = last(Indicators.cci(high, low, close, 20))
        t.williamsR = last(Indicators.williamsR(high, low, close, 14))
        t.momentum10 = last(Indicators.momentum(close, 10))
        t.roc12 = last(Indicators.roc(close, 12))
        t.mfi14 = last(Indicators.mfi(high, low, close, vol, 14))

        let sup = Indicators.supertrend(high, low, close)
        t.supertrend = last(sup.line)
        t.supertrendUp = sup.up.last ?? true

        // MARK: Extended volatility
        let kelt = Indicators.keltner(high, low, close)
        t.keltnerUpper = last(kelt.upper); t.keltnerMiddle = last(kelt.middle); t.keltnerLower = last(kelt.lower)
        let don = Indicators.donchian(high, low, 20)
        t.donchianUpper = last(don.upper); t.donchianMiddle = last(don.middle); t.donchianLower = last(don.lower)
        t.stdDev = last(Indicators.stdev(close, 20))
        t.historicalVol = last(Indicators.historicalVolatility(close, 20))
        t.chaikinVol = last(Indicators.chaikinVolatility(high, low, 10))
        t.massIndex = last(Indicators.massIndex(high, low))
        t.ulcerIndex = last(Indicators.ulcerIndex(close, 14))
        t.choppinessIndex = last(Indicators.choppinessIndex(high, low, close, 14))

        // MARK: Extended momentum
        t.trix = last(Indicators.trix(close, 15))
        t.ultimateOsc = last(Indicators.ultimateOscillator(high, low, close))
        t.cmo = last(Indicators.cmo(close, 14))
        let ppo = Indicators.ppo(close)
        t.ppoLine = last(ppo.line); t.ppoSignal = last(ppo.signal); t.ppoHistogram = last(ppo.histogram)
        t.fisherTransform = last(Indicators.fisherTransform(high, low, 10))
        t.priceZScore = last(Indicators.zScore(close, 20))
        t.efficiencyRatio = last(Indicators.efficiencyRatio(close, 10))

        // MARK: Extended direction / trend
        let psar = Indicators.parabolicSAR(high, low)
        t.psar = last(psar.sar); t.psarUp = psar.up.last ?? true
        t.psarTrend = t.psarUp ? "up" : "down"

        let ich = Indicators.ichimoku(high, low, close)
        t.ichimokuTenkan = last(ich.tenkan); t.ichimokuKijun = last(ich.kijun)
        t.ichimokuSenkouA = last(ich.senkouA); t.ichimokuSenkouB = last(ich.senkouB)

        let gann = Indicators.gannHiLo(high, low, close, 10)
        t.gannUp = gann.up.last ?? true

        let piv = Indicators.pivotPoints(high, low, close)
        t.pivot = last(piv.pivot); t.pivotR1 = last(piv.r1); t.pivotS1 = last(piv.s1)

        t.hullFast = last(MA.hma(close, 21)); t.hullSlow = last(MA.hma(close, 55))

        let ha = Indicators.heikinAshi(md.opens, high, low, close)
        t.heikinBullish = (ha.close.last ?? 0) >= (ha.open.last ?? 0)

        t.linRegSlope = last(Indicators.linRegSlope(close, 14))

        let aroon = Indicators.aroon(high, low, 25)
        t.aroonUp = last(aroon.up); t.aroonDown = last(aroon.down); t.aroonOscillator = last(aroon.oscillator)
        let vortex = Indicators.vortex(high, low, close, 14)
        t.vortexPlus = last(vortex.plus); t.vortexMinus = last(vortex.minus)

        // MARK: Extended volume
        t.adLine = last(Indicators.adLine(high, low, close, vol))
        t.cmf = last(Indicators.cmf(high, low, close, vol, 20))
        t.volumeOsc = last(Indicators.volumeOscillator(vol))
        t.eom = last(Indicators.eom(high, low, vol, 14))
        t.nvi = last(Indicators.nvi(close, vol))
        t.pvi = last(Indicators.pvi(close, vol))
        t.vwap = last(Indicators.vwap(high, low, close, vol))
        t.forceIndex = last(Indicators.forceIndex(close, vol, 13))
        t.relativeVolume = last(Indicators.relativeVolume(vol, 20))

        // Trend strength: directional strength, EMA alignment, and price-path efficiency.
        let emaAligned = (t.ema12 > t.ema26 && t.ema50 > t.ema200) || (t.ema12 < t.ema26 && t.ema50 < t.ema200)
        let directionalAgreement = abs(t.aroonOscillator) >= 50 && abs(t.vortexPlus - t.vortexMinus) >= 0.1
        t.trendStrength = min(100, t.adx + (emaAligned ? 15 : 0) + (directionalAgreement ? 10 : 0) + t.efficiencyRatio * 10)

        return t
    }
}
