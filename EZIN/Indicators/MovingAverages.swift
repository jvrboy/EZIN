import Foundation

/// Moving averages — faithful port of utils/MovingAverages.jsx
/// (SMA, EMA, RMA, WMA, DEMA, TEMA, HMA, VWMA, KAMA).
enum MA {

    static func sma(_ src: [Double], _ len: Int) -> [Double] {
        src.indices.map { i in
            guard i >= len - 1 else { return 0 }
            var s = 0.0
            for j in (i - len + 1)...i { s += src[j] }
            return s / Double(len)
        }
    }

    static func ema(_ src: [Double], _ len: Int) -> [Double] {
        let k = 2.0 / Double(len + 1)
        var out = [Double]()
        for (i, v) in src.enumerated() {
            out.append(i == 0 ? v : v * k + out[i - 1] * (1 - k))
        }
        return out
    }

    /// Wilder's smoothing (RMA) — used by RSI / ATR.
    static func rma(_ src: [Double], _ len: Int) -> [Double] {
        let alpha = 1.0 / Double(len)
        var out = [Double]()
        for (i, v) in src.enumerated() {
            out.append(i == 0 ? v : alpha * v + (1 - alpha) * out[i - 1])
        }
        return out
    }

    static func wma(_ src: [Double], _ len: Int) -> [Double] {
        src.indices.map { i in
            guard i >= len - 1 else { return 0 }
            var num = 0.0, den = 0.0
            for j in 0..<len { num += src[i - j] * Double(len - j); den += Double(len - j) }
            return num / den
        }
    }

    static func dema(_ src: [Double], _ len: Int) -> [Double] {
        let e1 = ema(src, len), e2 = ema(e1, len)
        return src.indices.map { 2 * e1[$0] - e2[$0] }
    }

    static func tema(_ src: [Double], _ len: Int) -> [Double] {
        let e1 = ema(src, len), e2 = ema(e1, len), e3 = ema(e2, len)
        return src.indices.map { 3 * e1[$0] - 3 * e2[$0] + e3[$0] }
    }

    static func hma(_ src: [Double], _ len: Int) -> [Double] {
        let half = len / 2
        let sqrtLen = Int(Double(len).squareRoot())
        let w1 = wma(src, max(half, 1)), w2 = wma(src, len)
        let raw = src.indices.map { 2 * w1[$0] - w2[$0] }
        return wma(raw, max(sqrtLen, 1))
    }

    static func vwma(_ src: [Double], _ vol: [Double], _ len: Int) -> [Double] {
        src.indices.map { i in
            guard i >= len - 1 else { return 0 }
            var num = 0.0, den = 0.0
            for j in (i - len + 1)...i { num += src[j] * vol[j]; den += vol[j] }
            return den != 0 ? num / den : 0
        }
    }

    static func kama(_ src: [Double], _ len: Int = 10, _ fast: Int = 2, _ slow: Int = 30) -> [Double] {
        let fastSC = 2.0 / Double(fast + 1), slowSC = 2.0 / Double(slow + 1)
        var out = [Double]()
        for (i, v) in src.enumerated() {
            if i < len { out.append(v); continue }
            let change = abs(v - src[i - len])
            var vol = 0.0
            for j in (i - len + 1)...i { vol += abs(src[j] - src[j - 1]) }
            let er = vol != 0 ? change / vol : 0
            let sc = pow(er * (fastSC - slowSC) + slowSC, 2)
            out.append(out[i - 1] + sc * (v - out[i - 1]))
        }
        return out
    }
}
