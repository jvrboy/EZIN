import Foundation

/// Pivot + divergence detection — faithful port of utils/DivergenceEngine.jsx.
enum DivergenceEngine {

    struct Pivot { let index: Int; let value: Double }

    enum DivergenceType: String {
        case regularBullish = "regular_bullish"
        case regularBearish = "regular_bearish"
        case hiddenBullish  = "hidden_bullish"
        case hiddenBearish  = "hidden_bearish"
        var isBullish: Bool { self == .regularBullish || self == .hiddenBullish }
        var isHidden: Bool { self == .hiddenBullish || self == .hiddenBearish }
    }

    struct Divergence { let type: DivergenceType; let at: Int; let price: Double; let ind: Double }

    static func findPivots(_ arr: [Double], leftBars: Int = 5, rightBars: Int = 5)
        -> (highs: [Pivot], lows: [Pivot]) {
        var highs = [Pivot](), lows = [Pivot]()
        guard arr.count > leftBars + rightBars else { return (highs, lows) }
        for i in leftBars..<(arr.count - rightBars) {
            var isHigh = true, isLow = true
            for j in (i - leftBars)...(i + rightBars) where j != i {
                if arr[j] >= arr[i] { isHigh = false }
                if arr[j] <= arr[i] { isLow = false }
            }
            if isHigh { highs.append(Pivot(index: i, value: arr[i])) }
            if isLow { lows.append(Pivot(index: i, value: arr[i])) }
        }
        return (highs, lows)
    }

    static func detect(price: [Double], indicator: [Double],
                       leftBars: Int = 5, rightBars: Int = 5, lookback: Int = 60) -> [Divergence] {
        let p = findPivots(price, leftBars: leftBars, rightBars: rightBars)
        let ind = findPivots(indicator, leftBars: leftBars, rightBars: rightBars)

        func pair(_ pArr: [Pivot], _ iArr: [Pivot]) -> [(pIdx: Int, pVal: Double, iVal: Double)] {
            var out = [(Int, Double, Double)]()
            for pv in pArr {
                if let m = iArr.first(where: { abs($0.index - pv.index) <= rightBars + 1 }) {
                    out.append((pv.index, pv.value, m.value))
                }
            }
            return out
        }

        var signals = [Divergence]()
        let highs = pair(p.highs, ind.highs)
        let lows = pair(p.lows, ind.lows)

        for i in 1..<max(highs.count, 1) {
            guard highs.count > 1 else { break }
            let a = highs[i - 1], b = highs[i]
            if b.pIdx - a.pIdx > lookback { continue }
            if b.pVal > a.pVal && b.iVal < a.iVal {
                signals.append(Divergence(type: .regularBearish, at: b.pIdx, price: b.pVal, ind: b.iVal))
            }
            if b.pVal < a.pVal && b.iVal > a.iVal {
                signals.append(Divergence(type: .hiddenBearish, at: b.pIdx, price: b.pVal, ind: b.iVal))
            }
        }
        for i in 1..<max(lows.count, 1) {
            guard lows.count > 1 else { break }
            let a = lows[i - 1], b = lows[i]
            if b.pIdx - a.pIdx > lookback { continue }
            if b.pVal < a.pVal && b.iVal > a.iVal {
                signals.append(Divergence(type: .regularBullish, at: b.pIdx, price: b.pVal, ind: b.iVal))
            }
            if b.pVal > a.pVal && b.iVal < a.iVal {
                signals.append(Divergence(type: .hiddenBullish, at: b.pIdx, price: b.pVal, ind: b.iVal))
            }
        }
        return signals
    }
}

/// Spike detectors — ports of indicators/spike/PriceSpike.jsx + VolatilitySpike.jsx.
enum Spike {
    struct PriceSpike { let spike: Bool; let strength: Double; let up: Bool }

    static func price(open: [Double], high: [Double], low: [Double], close: [Double],
                      len: Int = 20, mult: Double = 2.5) -> [PriceSpike] {
        let range = high.indices.map { high[$0] - low[$0] }
        let avg = MA.sma(range, len)
        return close.indices.map { i in
            let strength = avg[i] != 0 ? range[i] / avg[i] : 0
            return PriceSpike(spike: range[i] > avg[i] * mult, strength: strength, up: close[i] > open[i])
        }
    }

    static func volatility(high: [Double], low: [Double], close: [Double],
                           atrLen: Int = 14, avgLen: Int = 50, mult: Double = 2) -> [(spike: Bool, ratio: Double)] {
        let atr = Indicators.atr(high, low, close, atrLen)
        let avg = MA.sma(atr, avgLen)
        return atr.indices.map { i in (atr[i] > avg[i] * mult, avg[i] != 0 ? atr[i] / avg[i] : 0) }
    }
}
