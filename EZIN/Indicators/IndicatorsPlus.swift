import Foundation

/// Extended indicator library — volatility, momentum, direction, trend, and volume
/// studies added for deeper multi-indicator confluence.
extension Indicators {

    // MARK: - Volatility

    static func stdev(_ src: [Double], _ len: Int = 20) -> [Double] {
        let mean = MA.sma(src, len)
        var out = [Double](repeating: 0, count: src.count)
        for i in src.indices where i >= len - 1 {
            var s = 0.0
            for j in (i - len + 1)...i { s += pow(src[j] - mean[i], 2) }
            out[i] = (s / Double(len)).squareRoot()
        }
        return out
    }

    static func keltner(_ high: [Double], _ low: [Double], _ close: [Double],
                        len: Int = 20, mult: Double = 2, atrLen: Int = 10)
        -> (upper: [Double], middle: [Double], lower: [Double]) {
        let mid = MA.ema(close, len)
        let a = atr(high, low, close, atrLen)
        let upper = close.indices.map { mid[$0] + mult * a[$0] }
        let lower = close.indices.map { mid[$0] - mult * a[$0] }
        return (upper, mid, lower)
    }

    static func donchian(_ high: [Double], _ low: [Double], _ len: Int = 20)
        -> (upper: [Double], middle: [Double], lower: [Double]) {
        let n = high.count
        var upper = [Double](repeating: 0, count: n)
        var lower = [Double](repeating: 0, count: n)
        var mid = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - len + 1)
            let hh = high[lo...i].max() ?? high[i]
            let ll = low[lo...i].min() ?? low[i]
            upper[i] = hh; lower[i] = ll; mid[i] = (hh + ll) / 2
        }
        return (upper, mid, lower)
    }

    static func historicalVolatility(_ close: [Double], _ len: Int = 20) -> [Double] {
        var rets = [Double](repeating: 0, count: close.count)
        for i in close.indices where i > 0 && close[i - 1] > 0 {
            rets[i] = log(close[i] / close[i - 1])
        }
        return stdev(rets, len).map { $0 * 100 }
    }

    static func chaikinVolatility(_ high: [Double], _ low: [Double], _ len: Int = 10) -> [Double] {
        let hl = high.indices.map { high[$0] - low[$0] }
        let e = MA.ema(hl, len)
        return e.indices.map { i in
            i >= len && e[i - len] != 0 ? (e[i] - e[i - len]) / e[i - len] * 100 : 0
        }
    }

    static func massIndex(_ high: [Double], _ low: [Double], emaLen: Int = 9, sumLen: Int = 25) -> [Double] {
        let hl = high.indices.map { high[$0] - low[$0] }
        let e1 = MA.ema(hl, emaLen)
        let e2 = MA.ema(e1, emaLen)
        let ratio = e1.indices.map { e2[$0] != 0 ? e1[$0] / e2[$0] : 0 }
        var out = [Double](repeating: 0, count: ratio.count)
        for i in ratio.indices where i >= sumLen - 1 {
            var s = 0.0
            for j in (i - sumLen + 1)...i { s += ratio[j] }
            out[i] = s
        }
        return out
    }

    static func ulcerIndex(_ close: [Double], _ len: Int = 14) -> [Double] {
        var out = [Double](repeating: 0, count: close.count)
        for i in close.indices where i >= len - 1 {
            var sumSq = 0.0
            for idx in (i - len + 1)...i {
                let maxC = close[(i - len + 1)...idx].max() ?? close[idx]
                let dd = maxC != 0 ? (close[idx] - maxC) / maxC * 100 : 0
                sumSq += dd * dd
            }
            out[i] = (sumSq / Double(len)).squareRoot()
        }
        return out
    }

    // MARK: - Momentum

    static func trix(_ close: [Double], _ len: Int = 15) -> [Double] {
        let e1 = MA.ema(close, len)
        let e2 = MA.ema(e1, len)
        let e3 = MA.ema(e2, len)
        return e3.indices.map { i in
            i > 0 && e3[i - 1] != 0 ? (e3[i] - e3[i - 1]) / e3[i - 1] * 100 : 0
        }
    }

    static func ultimateOscillator(_ high: [Double], _ low: [Double], _ close: [Double],
                                   s: Int = 7, m: Int = 14, l: Int = 28) -> [Double] {
        let n = close.count
        var bp = [Double](repeating: 0, count: n)
        var tr = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if i == 0 { bp[i] = 0; tr[i] = high[i] - low[i]; continue }
            let trueLow = min(low[i], close[i - 1])
            bp[i] = close[i] - trueLow
            tr[i] = max(high[i], close[i - 1]) - trueLow
        }
        func avg(_ len: Int, _ i: Int) -> Double {
            guard i >= len - 1 else { return 0 }
            var sbp = 0.0, str = 0.0
            for j in (i - len + 1)...i { sbp += bp[j]; str += tr[j] }
            return str != 0 ? sbp / str : 0
        }
        var out = [Double](repeating: 50, count: n)
        for i in 0..<n where i >= l - 1 {
            let a1 = avg(s, i), a2 = avg(m, i), a3 = avg(l, i)
            out[i] = 100 * (4 * a1 + 2 * a2 + a3) / 7
        }
        return out
    }

    static func cmo(_ close: [Double], _ len: Int = 14) -> [Double] {
        let n = close.count
        var up = [Double](repeating: 0, count: n)
        var dn = [Double](repeating: 0, count: n)
        for i in 1..<max(n, 1) {
            let d = close[i] - close[i - 1]
            up[i] = d > 0 ? d : 0
            dn[i] = d < 0 ? -d : 0
        }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n where i >= len {
            var su = 0.0, sd = 0.0
            for j in (i - len + 1)...i { su += up[j]; sd += dn[j] }
            out[i] = (su + sd) != 0 ? (su - sd) / (su + sd) * 100 : 0
        }
        return out
    }

    // MARK: - Direction / Trend

    static func ichimoku(_ high: [Double], _ low: [Double], _ close: [Double],
                        conv: Int = 9, base: Int = 26, spanB: Int = 52)
        -> (tenkan: [Double], kijun: [Double], senkouA: [Double], senkouB: [Double]) {
        let n = close.count
        func midline(_ len: Int, _ i: Int) -> Double {
            let lo = max(0, i - len + 1)
            let hh = high[lo...i].max() ?? high[i]
            let ll = low[lo...i].min() ?? low[i]
            return (hh + ll) / 2
        }
        var tenkan = [Double](repeating: 0, count: n)
        var kijun = [Double](repeating: 0, count: n)
        var senkouA = [Double](repeating: 0, count: n)
        var senkouB = [Double](repeating: 0, count: n)
        for i in 0..<n {
            tenkan[i] = midline(conv, i)
            kijun[i] = midline(base, i)
            senkouA[i] = (tenkan[i] + kijun[i]) / 2
            senkouB[i] = midline(spanB, i)
        }
        return (tenkan, kijun, senkouA, senkouB)
    }

    static func gannHiLo(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 10)
        -> (line: [Double], up: [Bool]) {
        let n = close.count
        let hAvg = MA.sma(high, len)
        let lAvg = MA.sma(low, len)
        var up = [Bool](repeating: true, count: n)
        var line = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if i == 0 { up[i] = true; line[i] = lAvg[i]; continue }
            if close[i] > hAvg[i - 1] { up[i] = true }
            else if close[i] < lAvg[i - 1] { up[i] = false }
            else { up[i] = up[i - 1] }
            line[i] = up[i] ? lAvg[i] : hAvg[i]
        }
        return (line, up)
    }

    static func pivotPoints(_ high: [Double], _ low: [Double], _ close: [Double])
        -> (pivot: [Double], r1: [Double], s1: [Double]) {
        let n = close.count
        var p = [Double](repeating: 0, count: n)
        var r1 = [Double](repeating: 0, count: n)
        var s1 = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let j = max(0, i - 1)
            let pivot = (high[j] + low[j] + close[j]) / 3
            p[i] = pivot
            r1[i] = 2 * pivot - low[j]
            s1[i] = 2 * pivot - high[j]
        }
        return (p, r1, s1)
    }

    static func linRegSlope(_ src: [Double], _ len: Int = 14) -> [Double] {
        let n = src.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n where i >= len - 1 {
            var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0
            for k in 0..<len {
                let x = Double(k)
                let y = src[i - len + 1 + k]
                sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x
            }
            let d = Double(len) * sumX2 - sumX * sumX
            out[i] = d != 0 ? (Double(len) * sumXY - sumX * sumY) / d : 0
        }
        return out
    }

    static func parabolicSAR(_ high: [Double], _ low: [Double], step: Double = 0.02, maxStep: Double = 0.2)
        -> (sar: [Double], up: [Bool]) {
        let n = high.count
        var sar = [Double](repeating: 0, count: n)
        var up = [Bool](repeating: true, count: n)
        guard n > 1 else { return (high, up) }
        var uptrend = true
        var af = step
        var ep = high[0]
        sar[0] = low[0]
        for i in 1..<n {
            sar[i] = sar[i - 1] + af * (ep - sar[i - 1])
            if uptrend {
                if low[i] < sar[i] {
                    uptrend = false; sar[i] = ep; ep = low[i]; af = step
                } else if high[i] > ep { ep = high[i]; af = min(af + step, maxStep) }
            } else {
                if high[i] > sar[i] {
                    uptrend = true; sar[i] = ep; ep = high[i]; af = step
                } else if low[i] < ep { ep = low[i]; af = min(af + step, maxStep) }
            }
            up[i] = uptrend
        }
        return (sar, up)
    }

    // MARK: - Trend shape

    static func heikinAshi(_ open: [Double], _ high: [Double], _ low: [Double], _ close: [Double])
        -> (open: [Double], high: [Double], low: [Double], close: [Double]) {
        let n = close.count
        var ho = [Double](repeating: 0, count: n)
        var hc = [Double](repeating: 0, count: n)
        var hh = [Double](repeating: 0, count: n)
        var hl = [Double](repeating: 0, count: n)
        for i in 0..<n {
            hc[i] = (open[i] + high[i] + low[i] + close[i]) / 4
            ho[i] = i == 0 ? (open[i] + close[i]) / 2 : (ho[i - 1] + hc[i - 1]) / 2
            hh[i] = max(high[i], max(ho[i], hc[i]))
            hl[i] = min(low[i], min(ho[i], hc[i]))
        }
        return (ho, hh, hl, hc)
    }

    // MARK: - Volume

    static func adLine(_ high: [Double], _ low: [Double], _ close: [Double], _ volume: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: close.count)
        for i in close.indices {
            let rng = high[i] - low[i]
            let mfm = rng != 0 ? ((close[i] - low[i]) - (high[i] - close[i])) / rng : 0
            let mfv = mfm * volume[i]
            out[i] = i == 0 ? mfv : out[i - 1] + mfv
        }
        return out
    }

    static func cmf(_ high: [Double], _ low: [Double], _ close: [Double], _ volume: [Double], _ len: Int = 20) -> [Double] {
        let n = close.count
        var mfv = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let rng = high[i] - low[i]
            let mfm = rng != 0 ? ((close[i] - low[i]) - (high[i] - close[i])) / rng : 0
            mfv[i] = mfm * volume[i]
        }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n where i >= len - 1 {
            var sv = 0.0, svol = 0.0
            for j in (i - len + 1)...i { sv += mfv[j]; svol += volume[j] }
            out[i] = svol != 0 ? sv / svol : 0
        }
        return out
    }

    static func volumeOscillator(_ volume: [Double], fast: Int = 5, slow: Int = 10) -> [Double] {
        let f = MA.ema(volume, fast), s = MA.ema(volume, slow)
        return volume.indices.map { s[$0] != 0 ? (f[$0] - s[$0]) / s[$0] * 100 : 0 }
    }

    static func eom(_ high: [Double], _ low: [Double], _ volume: [Double], _ len: Int = 14) -> [Double] {
        let n = high.count
        var raw = [Double](repeating: 0, count: n)
        for i in 1..<max(n, 1) {
            let hl2 = (high[i] + low[i]) / 2
            let prevHl2 = (high[i - 1] + low[i - 1]) / 2
            let dist = hl2 - prevHl2
            let rng = high[i] - low[i]
            let boxRatio = (volume[i] != 0 && rng != 0) ? (volume[i] / 100000000.0) / rng : 0
            raw[i] = boxRatio != 0 ? dist / boxRatio : 0
        }
        return MA.sma(raw, len)
    }

    static func nvi(_ close: [Double], _ volume: [Double]) -> [Double] {
        var out = [Double](repeating: 1000, count: close.count)
        for i in close.indices where i > 0 {
            if volume[i] < volume[i - 1] && close[i - 1] != 0 {
                out[i] = out[i - 1] + (close[i] - close[i - 1]) / close[i - 1] * out[i - 1]
            } else { out[i] = out[i - 1] }
        }
        return out
    }

    static func pvi(_ close: [Double], _ volume: [Double]) -> [Double] {
        var out = [Double](repeating: 1000, count: close.count)
        for i in close.indices where i > 0 {
            if volume[i] > volume[i - 1] && close[i - 1] != 0 {
                out[i] = out[i - 1] + (close[i] - close[i - 1]) / close[i - 1] * out[i - 1]
            } else { out[i] = out[i - 1] }
        }
        return out
    }

    static func vwap(_ high: [Double], _ low: [Double], _ close: [Double], _ volume: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: close.count)
        var cumPV = 0.0, cumV = 0.0
        for i in close.indices {
            let tp = (high[i] + low[i] + close[i]) / 3
            cumPV += tp * volume[i]
            cumV += volume[i]
            out[i] = cumV != 0 ? cumPV / cumV : tp
        }
        return out
    }

    static func forceIndex(_ close: [Double], _ volume: [Double], _ len: Int = 13) -> [Double] {
        var raw = [Double](repeating: 0, count: close.count)
        for i in close.indices where i > 0 { raw[i] = (close[i] - close[i - 1]) * volume[i] }
        return MA.ema(raw, len)
    }

    static func relativeVolume(_ volume: [Double], _ len: Int = 20) -> [Double] {
        let average = MA.sma(volume, len)
        return volume.indices.map { average[$0] > 0 ? volume[$0] / average[$0] : 1 }
    }

    // MARK: - Advanced momentum and market regime

    static func ppo(_ close: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9)
        -> (line: [Double], signal: [Double], histogram: [Double]) {
        let fastEMA = MA.ema(close, fast)
        let slowEMA = MA.ema(close, slow)
        let line = close.indices.map { slowEMA[$0] != 0 ? (fastEMA[$0] - slowEMA[$0]) / slowEMA[$0] * 100 : 0 }
        let signalLine = MA.ema(line, signal)
        let histogram = close.indices.map { line[$0] - signalLine[$0] }
        return (line, signalLine, histogram)
    }

    static func zScore(_ src: [Double], _ len: Int = 20) -> [Double] {
        let mean = MA.sma(src, len)
        let deviation = stdev(src, len)
        return src.indices.map { deviation[$0] > 0 ? (src[$0] - mean[$0]) / deviation[$0] : 0 }
    }

    static func efficiencyRatio(_ close: [Double], _ len: Int = 10) -> [Double] {
        var out = [Double](repeating: 0, count: close.count)
        guard close.count > len else { return out }
        for i in len..<close.count {
            let direction = abs(close[i] - close[i - len])
            var volatility = 0.0
            for j in (i - len + 1)...i { volatility += abs(close[j] - close[j - 1]) }
            out[i] = volatility > 0 ? direction / volatility : 0
        }
        return out
    }

    static func fisherTransform(_ high: [Double], _ low: [Double], _ len: Int = 10) -> [Double] {
        let n = min(high.count, low.count)
        var out = [Double](repeating: 0, count: n)
        var normalized = 0.0
        guard n > 0 else { return out }
        for i in 0..<n {
            let start = max(0, i - len + 1)
            let highest = high[start...i].max() ?? high[i]
            let lowest = low[start...i].min() ?? low[i]
            let median = (high[i] + low[i]) / 2
            let raw = highest > lowest ? 2 * ((median - lowest) / (highest - lowest) - 0.5) : 0
            normalized = max(-0.999, min(0.999, 0.66 * raw + 0.67 * normalized))
            let fisher = 0.5 * log((1 + normalized) / (1 - normalized))
            out[i] = i == 0 ? fisher : 0.5 * fisher + 0.5 * out[i - 1]
        }
        return out
    }

    static func aroon(_ high: [Double], _ low: [Double], _ len: Int = 25)
        -> (up: [Double], down: [Double], oscillator: [Double]) {
        let n = min(high.count, low.count)
        var up = [Double](repeating: 50, count: n)
        var down = [Double](repeating: 50, count: n)
        let period = max(2, len)
        guard n >= period else { return (up, down, zip(up, down).map { $0 - $1 }) }
        for i in (period - 1)..<n {
            let start = i - period + 1
            var highIndex = start, lowIndex = start
            for j in (start + 1)...i {
                if high[j] >= high[highIndex] { highIndex = j }
                if low[j] <= low[lowIndex] { lowIndex = j }
            }
            up[i] = 100 * Double(period - 1 - (i - highIndex)) / Double(period - 1)
            down[i] = 100 * Double(period - 1 - (i - lowIndex)) / Double(period - 1)
        }
        return (up, down, zip(up, down).map { $0 - $1 })
    }

    static func vortex(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 14)
        -> (plus: [Double], minus: [Double]) {
        let n = min(high.count, min(low.count, close.count))
        var plus = [Double](repeating: 1, count: n)
        var minus = [Double](repeating: 1, count: n)
        guard n > 1 else { return (plus, minus) }
        var tr = [Double](repeating: 0, count: n)
        var vmPlus = [Double](repeating: 0, count: n)
        var vmMinus = [Double](repeating: 0, count: n)
        for i in 1..<n {
            tr[i] = max(high[i] - low[i], max(abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1])))
            vmPlus[i] = abs(high[i] - low[i - 1])
            vmMinus[i] = abs(low[i] - high[i - 1])
        }
        guard n > len else { return (plus, minus) }
        for i in len..<n {
            var trSum = 0.0, plusSum = 0.0, minusSum = 0.0
            for j in (i - len + 1)...i { trSum += tr[j]; plusSum += vmPlus[j]; minusSum += vmMinus[j] }
            if trSum > 0 { plus[i] = plusSum / trSum; minus[i] = minusSum / trSum }
        }
        return (plus, minus)
    }

    static func choppinessIndex(_ high: [Double], _ low: [Double], _ close: [Double], _ len: Int = 14) -> [Double] {
        let n = min(high.count, min(low.count, close.count))
        var out = [Double](repeating: 50, count: n)
        guard n > len, len > 1 else { return out }
        var tr = [Double](repeating: 0, count: n)
        for i in 1..<n {
            tr[i] = max(high[i] - low[i], max(abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1])))
        }
        for i in len..<n {
            let start = i - len + 1
            let range = (high[start...i].max() ?? high[i]) - (low[start...i].min() ?? low[i])
            var trSum = 0.0
            for j in start...i { trSum += tr[j] }
            if range > 0, trSum > 0 { out[i] = 100 * log10(trSum / range) / log10(Double(len)) }
        }
        return out
    }
}
