import Foundation

/// Computes the full TechnicalIndicators snapshot from market data
/// (port of analysis.indicators.TechnicalAnalyzer.analyze).
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
        return t
    }
}
