import Foundation

// MARK: - Microstructure, order-flow & profile studies
//
// These add the "market microstructure" layer requested for deeper confluence:
//   • Volume Profile (POC / Value Area High / Value Area Low)
//   • Market Profile (TPO letters per price bin)
//   • Order-flow proxies (net aggressive volume, trade-direction ratio)
//   • Realized volatility (rolling stdev of log returns) + jump detection (MAD)
//   • Volatility regime classification (calm / normal / high / ultra-high)
//   • Liquidity heatmap levels (clustered highs/lows likely holding resting orders)
//
// Deriv candle history exposes OHLCV but not the true bid/ask trade side, so the
// order-flow figures are *candle-derived proxies*: they estimate aggression from
// where price closed inside each bar and how volume/range behaved. They are named
// `…Proxy` so the rest of the app never mistakes them for tick-level truth.

enum Microstructure {

    // MARK: Volume Profile

    struct VolumeProfile {
        let poc: Double            // point of control (price with most volume)
        let valueAreaHigh: Double
        let valueAreaLow: Double
        let bins: [(price: Double, volume: Double)]
        var valueAreaWidth: Double { valueAreaHigh - valueAreaLow }
    }

    /// Build a volume-at-price histogram and derive POC + 70% value area.
    static func volumeProfile(high: [Double], low: [Double], close: [Double],
                              volume: [Double], bins binCount: Int = 24) -> VolumeProfile? {
        guard close.count > 5, let lo = low.min(), let hi = high.max(), hi > lo else { return nil }
        let step = (hi - lo) / Double(binCount)
        guard step > 0 else { return nil }
        var buckets = [Double](repeating: 0, count: binCount)
        for i in close.indices {
            // Spread each bar's volume across the bins its range covers.
            let vol = volume[i] > 0 ? volume[i] : 1               // synthetics often report 0 volume
            let barLo = low[i], barHi = high[i]
            let firstBin = max(0, min(binCount - 1, Int((barLo - lo) / step)))
            let lastBin  = max(0, min(binCount - 1, Int((barHi - lo) / step)))
            let span = max(1, lastBin - firstBin + 1)
            for b in firstBin...lastBin { buckets[b] += vol / Double(span) }
        }
        func priceForBin(_ b: Int) -> Double { lo + (Double(b) + 0.5) * step }

        let pocBin = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) ?? 0
        let total = buckets.reduce(0, +)
        // Expand around the POC until 70% of volume is captured (standard value area).
        var included = Set([pocBin]); var captured = buckets[pocBin]
        var lo2 = pocBin, hi2 = pocBin
        while captured < total * 0.7 && (lo2 > 0 || hi2 < binCount - 1) {
            let downVol = lo2 > 0 ? buckets[lo2 - 1] : -1
            let upVol   = hi2 < binCount - 1 ? buckets[hi2 + 1] : -1
            if upVol >= downVol && hi2 < binCount - 1 { hi2 += 1; included.insert(hi2); captured += buckets[hi2] }
            else if lo2 > 0 { lo2 -= 1; included.insert(lo2); captured += buckets[lo2] }
            else { break }
        }
        return VolumeProfile(
            poc: priceForBin(pocBin),
            valueAreaHigh: priceForBin(hi2),
            valueAreaLow: priceForBin(lo2),
            bins: buckets.indices.map { (priceForBin($0), buckets[$0]) }
        )
    }

    // MARK: Market Profile (TPO)

    struct MarketProfileRow { let price: Double; let tpoCount: Int }

    /// Time-Price-Opportunity distribution: how many bars touched each price bin.
    static func marketProfile(high: [Double], low: [Double], bins binCount: Int = 24) -> [MarketProfileRow] {
        guard high.count > 5, let lo = low.min(), let hi = high.max(), hi > lo else { return [] }
        let step = (hi - lo) / Double(binCount)
        var counts = [Int](repeating: 0, count: binCount)
        for i in high.indices {
            let firstBin = max(0, min(binCount - 1, Int((low[i] - lo) / step)))
            let lastBin  = max(0, min(binCount - 1, Int((high[i] - lo) / step)))
            for b in firstBin...lastBin { counts[b] += 1 }
        }
        return counts.indices.map { MarketProfileRow(price: lo + (Double($0) + 0.5) * step, tpoCount: counts[$0]) }
    }

    // MARK: Order-flow proxies

    struct OrderFlow {
        let netAggressiveVolumeProxy: Double   // buy pressure − sell pressure (rolling)
        let tradeDirectionRatioProxy: Double   // 0…1, share of "buy-side" bars
        let deltaTrendProxy: Double            // slope of cumulative delta
        let absorptionProxy: Double            // high volume + small range ⇒ absorption
        var bias: Direction {
            switch netAggressiveVolumeProxy {
            case let v where v > 0.15: return .bullish
            case let v where v < -0.15: return .bearish
            default: return .neutral
            }
        }
    }

    /// Estimate aggressive order flow from candle geometry over the last `window` bars.
    /// buyPressure = volume × ((close−low)/range), sellPressure = volume × ((high−close)/range).
    static func orderFlow(open: [Double], high: [Double], low: [Double], close: [Double],
                          volume: [Double], window: Int = 30) -> OrderFlow {
        let n = close.count
        guard n > 2 else { return OrderFlow(netAggressiveVolumeProxy: 0, tradeDirectionRatioProxy: 0.5, deltaTrendProxy: 0, absorptionProxy: 0) }
        let start = max(0, n - window)
        var cumDelta = [Double]()
        var buyBars = 0, totalBars = 0
        var running = 0.0
        var absorption = 0.0
        var totalVol = 0.0
        for i in start..<n {
            let rng = max(high[i] - low[i], 1e-9)
            let vol = volume[i] > 0 ? volume[i] : 1
            let buyPart  = vol * ((close[i] - low[i]) / rng)
            let sellPart = vol * ((high[i] - close[i]) / rng)
            let delta = buyPart - sellPart
            running += delta
            cumDelta.append(running)
            if close[i] >= open[i] { buyBars += 1 }
            totalBars += 1
            totalVol += vol
            // Absorption: lots of volume but the bar barely moved.
            let move = abs(close[i] - open[i])
            absorption += (move > 0 ? vol / (move + rng) : vol)
        }
        let net = totalVol > 0 ? running / totalVol : 0
        let ratio = totalBars > 0 ? Double(buyBars) / Double(totalBars) : 0.5
        let slope = Indicators.linRegSlope(cumDelta, min(cumDelta.count, 14)).last ?? 0
        let absNorm = totalVol > 0 ? absorption / totalVol : 0
        return OrderFlow(netAggressiveVolumeProxy: net,
                         tradeDirectionRatioProxy: ratio,
                         deltaTrendProxy: slope,
                         absorptionProxy: absNorm)
    }

    // MARK: Realized volatility & jumps

    /// Rolling realized volatility = stdev of log returns over `window`, annualising-free.
    static func realizedVolatility(_ close: [Double], window: Int = 20) -> Double {
        guard close.count > window + 1 else { return 0 }
        var rets = [Double]()
        for i in (close.count - window)..<close.count where i > 0 && close[i - 1] > 0 {
            rets.append(log(close[i] / close[i - 1]))
        }
        guard rets.count > 1 else { return 0 }
        let mean = rets.reduce(0, +) / Double(rets.count)
        let varr = rets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rets.count - 1)
        return sqrt(varr)
    }

    struct JumpEvent { let index: Int; let ret: Double; let up: Bool; let magnitude: Double }

    /// Detect return jumps beyond `mult × MAD` (median absolute deviation) — robust to outliers.
    static func detectJumps(_ close: [Double], mult: Double = 3.0, lookback: Int = 120) -> [JumpEvent] {
        guard close.count > 5 else { return [] }
        let start = max(1, close.count - lookback)
        var rets = [(idx: Int, r: Double)]()
        for i in start..<close.count where close[i - 1] > 0 { rets.append((i, log(close[i] / close[i - 1]))) }
        guard rets.count > 5 else { return [] }
        let values = rets.map { $0.r }.sorted()
        let median = values[values.count / 2]
        let absDev = rets.map { abs($0.r - median) }.sorted()
        let mad = absDev[absDev.count / 2]
        guard mad > 0 else { return [] }
        return rets.compactMap { e in
            let z = abs(e.r - median) / mad
            guard z >= mult else { return nil }
            return JumpEvent(index: e.idx, ret: e.r, up: e.r > 0, magnitude: z)
        }
    }

    // MARK: Volatility regime

    enum VolatilityRegime: String {
        case calm = "Calm", normal = "Normal", high = "High", ultra = "Ultra-High"
        var multiplier: Double {   // signal-frequency multiplier the scanner uses
            switch self {
            case .calm: return 0.8
            case .normal: return 1.0
            case .high: return 1.3
            case .ultra: return 1.6
            }
        }
    }

    /// Classify the current regime from realized vol vs its own recent baseline.
    static func regime(_ close: [Double]) -> VolatilityRegime {
        guard close.count > 60 else { return .normal }
        let recent = realizedVolatility(close, window: 14)
        let baseline = realizedVolatility(Array(close.prefix(close.count - 14)), window: 50)
        guard baseline > 0 else { return .normal }
        let ratio = recent / baseline
        switch ratio {
        case let r where r < 0.7: return .calm
        case let r where r < 1.3: return .normal
        case let r where r < 2.0: return .high
        default: return .ultra
        }
    }

    // MARK: Liquidity heatmap levels

    struct LiquidityLevel { let price: Double; let strength: Double; let isResistance: Bool }

    /// Cluster swing highs/lows into "liquidity pools" where resting orders likely sit.
    static func liquidityLevels(high: [Double], low: [Double], close: [Double],
                                lookback: Int = 120, maxLevels: Int = 6) -> [LiquidityLevel] {
        guard close.count > 20 else { return [] }
        let piv = DivergenceEngine.findPivots(high, leftBars: 3, rightBars: 3)
        let pivL = DivergenceEngine.findPivots(low, leftBars: 3, rightBars: 3)
        let price = close.last ?? 0
        let tol = (high.max()! - low.min()!) * 0.01
        var pools: [(price: Double, hits: Int, res: Bool)] = []
        func add(_ v: Double, res: Bool) {
            if let i = pools.firstIndex(where: { abs($0.price - v) <= tol }) {
                pools[i].hits += 1
            } else { pools.append((v, 1, res)) }
        }
        for p in piv.highs.suffix(lookback) { add(p.value, res: true) }
        for p in pivL.lows.suffix(lookback) { add(p.value, res: false) }
        return pools
            .map { LiquidityLevel(price: $0.price, strength: Double($0.hits), isResistance: $0.price >= price) }
            .sorted { $0.strength > $1.strength }
            .prefix(maxLevels)
            .map { $0 }
    }

    // MARK: Speed / velocity

    /// Price velocity = normalized rate-of-change of close over the last `n` bars
    /// (how fast price is travelling on this timeframe), plus acceleration.
    static func velocity(_ close: [Double], n: Int = 10) -> (speed: Double, accel: Double) {
        guard close.count > n + 2, close[close.count - 1 - n] != 0 else { return (0, 0) }
        let last = close[close.count - 1]
        let prev = close[close.count - 1 - n]
        let speed = (last - prev) / abs(prev) * 100
        let mid = close[close.count - 1 - n / 2]
        let firstHalf = (mid - prev) / abs(prev) * 100
        let secondHalf = (last - mid) / abs(mid == 0 ? 1 : mid) * 100
        return (speed, secondHalf - firstHalf)   // acceleration = change in half-window speed
    }
}
