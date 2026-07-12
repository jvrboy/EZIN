import Foundation

/// Core technical indicators — faithful ports of the forex-jsx indicator suite.
enum Indicators {

    // RSI — port of indicators/momentum/RSI.jsx
    static func rsi(_ close: [Double], _ len: Int = 14) -> [Double] {
        guard !close.isEmpty else { return [] }
        var gains = [Double](repeating: 0, count: close.count)
        var losses = [Double](repeating: 0, count: close.count)
        for i in close.indices where i > 0 {
            let d = close[i] - close[i - 1]
            gains[i] = d > 0 ? d : 0
            losses[i] = d < 0 ? -d : 0
        }
        let avgG = MA.rma(gains, len), avgL = MA.rma(losses, len)
        return close.indices.map { i in
            if avgL[i] == 0 { return 100 }
            let rs = avgG[i] / avgL[i]
            return 100 - 100 / (1 + rs)
        }
    }

    // MACD — port of indicators/momentum/MACD.jsx
    static func macd(_ close: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9)
        -> (macd: [Double], signal: [Double], histogram: [Double]) {
        let emaFast = MA.ema(close, fast), emaSlow = MA.ema(close, slow)
        let macd = close.indices.map { emaFast[$0] - emaSlow[$0] }
        let sig = MA.ema(macd, signal)
        let hist = macd.indices.map { macd[$0] - sig[$0] }
        return (macd, sig, hist)
    }

    // True Range + ATR — port of indicators/volatility/ATR.jsx
    static func trueRange(_ high: [Double], _ low: [Double], _ close: [Double]) -> [Double] {
        high.indices.map { i in
            if i == 0 { return high[i] - low[i] }
            return max(high[i] - low[i],
                       abs(high[i] - close[i - 1]),
                       abs(low[i] - close[i - 1]))
        }
    }
    static func atr(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 14) -> [Double] {
        MA.rma(trueRange(high, low, close), len)
    }

    // Bollinger Bands — port of indicators/volatility/BollingerBands.jsx
    static func bollinger(_ close: [Double], len: Int = 20, mult: Double = 2)
        -> (upper: [Double], middle: [Double], lower: [Double]) {
        let mid = MA.sma(close, len)
        var upper = [Double](repeating: 0, count: close.count)
        var lower = [Double](repeating: 0, count: close.count)
        for i in close.indices where i >= len - 1 {
            var sumSq = 0.0
            for j in (i - len + 1)...i { sumSq += pow(close[j] - mid[i], 2) }
            let sd = (sumSq / Double(len)).squareRoot()
            upper[i] = mid[i] + mult * sd
            lower[i] = mid[i] - mult * sd
        }
        return (upper, mid, lower)
    }

    // Stochastic — port of indicators/momentum/Stochastic.jsx
    static func stochastic(_ high: [Double], _ low: [Double], _ close: [Double],
                           kLen: Int = 14, dLen: Int = 3) -> (k: [Double], d: [Double]) {
        var k = [Double](repeating: 50, count: close.count)
        for i in close.indices where i >= kLen - 1 {
            let hh = high[(i - kLen + 1)...i].max() ?? high[i]
            let ll = low[(i - kLen + 1)...i].min() ?? low[i]
            k[i] = hh - ll != 0 ? (close[i] - ll) / (hh - ll) * 100 : 50
        }
        return (k, MA.sma(k, dLen))
    }

    // CCI — port of indicators/momentum/CCI.jsx
    static func cci(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 20) -> [Double] {
        let tp = close.indices.map { (high[$0] + low[$0] + close[$0]) / 3 }
        let smaTP = MA.sma(tp, len)
        var out = [Double](repeating: 0, count: close.count)
        for i in close.indices where i >= len - 1 {
            var md = 0.0
            for j in (i - len + 1)...i { md += abs(tp[j] - smaTP[i]) }
            md /= Double(len)
            out[i] = md != 0 ? (tp[i] - smaTP[i]) / (0.015 * md) : 0
        }
        return out
    }

    // Williams %R — port of indicators/momentum/WilliamsR.jsx
    static func williamsR(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 14) -> [Double] {
        var out = [Double](repeating: -50, count: close.count)
        for i in close.indices where i >= len - 1 {
            let hh = high[(i - len + 1)...i].max() ?? high[i]
            let ll = low[(i - len + 1)...i].min() ?? low[i]
            out[i] = hh - ll != 0 ? (hh - close[i]) / (hh - ll) * -100 : -50
        }
        return out
    }

    // Momentum & ROC
    static func momentum(_ close: [Double], _ len: Int = 10) -> [Double] {
        close.indices.map { i in i >= len ? close[i] - close[i - len] : 0 }
    }
    static func roc(_ close: [Double], _ len: Int = 12) -> [Double] {
        close.indices.map { i in i >= len && close[i - len] != 0 ? (close[i] - close[i - len]) / close[i - len] * 100 : 0 }
    }

    // OBV — port of indicators/volume/OBV.jsx
    static func obv(_ close: [Double], _ volume: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: close.count)
        for i in close.indices where i > 0 {
            if close[i] > close[i - 1] { out[i] = out[i - 1] + volume[i] }
            else if close[i] < close[i - 1] { out[i] = out[i - 1] - volume[i] }
            else { out[i] = out[i - 1] }
        }
        return out
    }

    // MFI — port of indicators/volume/MFI.jsx
    static func mfi(_ high: [Double], _ low: [Double], _ close: [Double], _ volume: [Double], _ len: Int = 14) -> [Double] {
        let tp = close.indices.map { (high[$0] + low[$0] + close[$0]) / 3 }
        var out = [Double](repeating: 50, count: close.count)
        for i in close.indices where i >= len {
            var pos = 0.0, neg = 0.0
            for j in (i - len + 1)...i where j > 0 {
                let raw = tp[j] * volume[j]
                if tp[j] > tp[j - 1] { pos += raw } else if tp[j] < tp[j - 1] { neg += raw }
            }
            out[i] = neg != 0 ? 100 - 100 / (1 + pos / neg) : 100
        }
        return out
    }

    // ADX / DMI — port of indicators/trend/ADX.jsx + DMI.jsx
    static func adx(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 14)
        -> (adx: [Double], plusDI: [Double], minusDI: [Double]) {
        let n = close.count
        var plusDM = [Double](repeating: 0, count: n)
        var minusDM = [Double](repeating: 0, count: n)
        for i in 1..<max(n, 1) {
            let up = high[i] - high[i - 1]
            let down = low[i - 1] - low[i]
            plusDM[i] = (up > down && up > 0) ? up : 0
            minusDM[i] = (down > up && down > 0) ? down : 0
        }
        let tr = trueRange(high, low, close)
        let atrS = MA.rma(tr, len)
        let plusS = MA.rma(plusDM, len)
        let minusS = MA.rma(minusDM, len)
        var plusDI = [Double](repeating: 0, count: n)
        var minusDI = [Double](repeating: 0, count: n)
        var dx = [Double](repeating: 0, count: n)
        for i in 0..<n {
            plusDI[i] = atrS[i] != 0 ? 100 * plusS[i] / atrS[i] : 0
            minusDI[i] = atrS[i] != 0 ? 100 * minusS[i] / atrS[i] : 0
            let sum = plusDI[i] + minusDI[i]
            dx[i] = sum != 0 ? 100 * abs(plusDI[i] - minusDI[i]) / sum : 0
        }
        return (MA.rma(dx, len), plusDI, minusDI)
    }

    // Supertrend — port of indicators/trend/Supertrend.jsx
    static func supertrend(_ high: [Double], _ low: [Double], _ close: [Double],
                           len: Int = 10, mult: Double = 3)
        -> (line: [Double], up: [Bool]) {
        let n = close.count
        let atrS = atr(high, low, close, len)
        var line = [Double](repeating: 0, count: n)
        var up = [Bool](repeating: true, count: n)
        for i in 0..<n {
            let hl2 = (high[i] + low[i]) / 2
            let upperBand = hl2 + mult * atrS[i]
            let lowerBand = hl2 - mult * atrS[i]
            if i == 0 { line[i] = lowerBand; up[i] = true; continue }
            if close[i] > line[i - 1] { up[i] = true }
            else if close[i] < line[i - 1] { up[i] = false }
            else { up[i] = up[i - 1] }
            line[i] = up[i] ? max(lowerBand, line[i - 1]) : min(upperBand, line[i - 1])
        }
        return (line, up)
    }
}
