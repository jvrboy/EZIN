import Foundation

/// APEX — the second-generation hidden backend analysis layer.
/// These engines run fully on-device and feed the agent council, the pipelines and the
/// chat tools as additional confluence inputs for signal generation. Deterministic,
/// auditable, advisory-only — no order routing.
enum ApexBackend {

    // MARK: - Shared helpers

    private static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    private static func sd(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs)
        return sqrt(xs.reduce(0) { $0 + pow($1 - m, 2) } / Double(xs.count - 1))
    }
    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
    private static func fmt(_ x: Double, _ p: Int = 3) -> String { String(format: "%.\(p)f", x) }
    private static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    private static func dirLabel(_ d: Direction) -> String { AdvancedBackend.dir(d) }

    // MARK: - 1. Candlestick Pattern Suite

    struct CandlePattern: Identifiable {
        let id = UUID()
        let name: String
        let index: Int          // candle index where the pattern completes
        let bullish: Bool
        let strength: Double    // 0...1
    }

    /// Detect high-value candlestick patterns across the series (most recent last).
    static func candlePatterns(_ md: MarketData) -> [CandlePattern] {
        let cs = md.candles
        guard cs.count >= 5 else { return [] }
        var out: [CandlePattern] = []

        func body(_ c: Candle) -> Double { c.close - c.open }
        func upperWick(_ c: Candle) -> Double { c.high - max(c.open, c.close) }
        func lowerWick(_ c: Candle) -> Double { min(c.open, c.close) - c.low }
        let avgRange = mean(cs.suffix(20).map { $0.range })

        for i in 2..<cs.count {
            let c = cs[i], p = cs[i - 1], pp = cs[i - 2]
            guard c.range > 0, p.range > 0 else { continue }

            // Engulfing
            if body(c) > 0, body(p) < 0, c.close >= p.open, c.open <= p.close, c.body > p.body * 1.1 {
                out.append(CandlePattern(name: "Bullish Engulfing", index: i, bullish: true, strength: clamp(c.body / max(avgRange, 1e-9) / 2, 0.4, 1)))
            }
            if body(c) < 0, body(p) > 0, c.open >= p.close, c.close <= p.open, c.body > p.body * 1.1 {
                out.append(CandlePattern(name: "Bearish Engulfing", index: i, bullish: false, strength: clamp(c.body / max(avgRange, 1e-9) / 2, 0.4, 1)))
            }
            // Hammer / Shooting star (small body, long wick)
            let bodyRatio = c.body / c.range
            if bodyRatio < 0.35, lowerWick(c) > c.body * 2, upperWick(c) < c.body {
                out.append(CandlePattern(name: "Hammer", index: i, bullish: true, strength: 0.62))
            }
            if bodyRatio < 0.35, upperWick(c) > c.body * 2, lowerWick(c) < c.body {
                out.append(CandlePattern(name: "Shooting Star", index: i, bullish: false, strength: 0.62))
            }
            // Doji (indecision)
            if bodyRatio < 0.1, c.range > avgRange * 0.5 {
                out.append(CandlePattern(name: "Doji", index: i, bullish: body(c) >= 0, strength: 0.35))
            }
            // Morning / Evening star (3-candle reversal)
            if body(pp) < 0, abs(body(p)) < pp.body * 0.5, body(c) > 0, c.close > (pp.open + pp.close) / 2 {
                out.append(CandlePattern(name: "Morning Star", index: i, bullish: true, strength: 0.75))
            }
            if body(pp) > 0, abs(body(p)) < pp.body * 0.5, body(c) < 0, c.close < (pp.open + pp.close) / 2 {
                out.append(CandlePattern(name: "Evening Star", index: i, bullish: false, strength: 0.75))
            }
            // Three white soldiers / black crows
            if i >= 2, body(c) > 0, body(p) > 0, body(pp) > 0, c.close > p.close, p.close > pp.close,
               c.open > p.open, p.open > pp.open {
                out.append(CandlePattern(name: "Three White Soldiers", index: i, bullish: true, strength: 0.8))
            }
            if i >= 2, body(c) < 0, body(p) < 0, body(pp) < 0, c.close < p.close, p.close < pp.close,
               c.open < p.open, p.open < pp.open {
                out.append(CandlePattern(name: "Three Black Crows", index: i, bullish: false, strength: 0.8))
            }
        }
        return out
    }

    static func patternReport(_ md: MarketData, symbol: String) -> String {
        let patterns = candlePatterns(md)
        let recent = patterns.suffix(12).reversed()
        var s = "## Candlestick Pattern Scan — \(symbol)\n\n"
        if recent.isEmpty {
            s += "No high-value patterns detected in the recent window. Indecision or smooth drift — lean on trend engines.\n"
            return s
        }
        let bull = patterns.suffix(10).filter { $0.bullish }.map { $0.strength }.reduce(0, +)
        let bear = patterns.suffix(10).filter { !$0.bullish }.map { $0.strength }.reduce(0, +)
        s += "| Pattern | Direction | Strength |\n|---|---|---|\n"
        for p in recent {
            s += "| \(p.name) | \(p.bullish ? "Bullish" : "Bearish") | \(pct(p.strength)) |\n"
        }
        let bias: Direction = bull > bear * 1.3 ? .bullish : bear > bull * 1.3 ? .bearish : .neutral
        s += "\n**Pattern pressure:** bullish \(fmt(bull, 2)) vs bearish \(fmt(bear, 2)) → \(dirLabel(bias)).\n"
        return s
    }

    // MARK: - 2. Market Profile (TPO-lite value area)

    struct MarketProfile {
        let pointOfControl: Double
        let valueAreaHigh: Double
        let valueAreaLow: Double
        let insideValueArea: Bool
        let positionLabel: String
    }

    /// Build a price-histogram profile: where did price spend time? 70% value area.
    static func marketProfile(_ md: MarketData, bins: Int = 24) -> MarketProfile? {
        let cs = Array(md.candles.suffix(120))
        guard cs.count >= 20 else { return nil }
        let hi = cs.map { $0.high }.max() ?? 0
        let lo = cs.map { $0.low }.min() ?? 0
        guard hi > lo else { return nil }
        let binSize = (hi - lo) / Double(bins)
        var weights = [Double](repeating: 0, count: bins)
        for c in cs {
            // Distribute each candle's "time" uniformly across the bins it spans.
            let start = max(0, Int((c.low - lo) / binSize))
            let end = min(bins - 1, Int((c.high - lo) / binSize))
            guard end >= start else { continue }
            let w = 1.0 / Double(end - start + 1)
            for b in start...end { weights[b] += w * max(c.volume, 1) }
        }
        let poc = weights.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        // Expand around POC until 70% of total weight is covered.
        let total = weights.reduce(0, +)
        var covered = weights[poc]
        var loB = poc, hiB = poc
        while covered < total * 0.7, (loB > 0 || hiB < bins - 1) {
            let down = loB > 0 ? weights[loB - 1] : -1
            let up = hiB < bins - 1 ? weights[hiB + 1] : -1
            if up >= down { hiB += 1; covered += max(up, 0) } else { loB -= 1; covered += max(down, 0) }
        }
        let price = md.currentPrice > 0 ? md.currentPrice : (cs.last?.close ?? 0)
        let vah = lo + Double(hiB + 1) * binSize
        let val = lo + Double(loB) * binSize
        let pocPrice = lo + (Double(poc) + 0.5) * binSize
        let inside = price <= vah && price >= val
        let label: String
        if inside { label = "inside value area" }
        else if price > vah { label = "above value area (acceptance of higher prices)" }
        else { label = "below value area (acceptance of lower prices)" }
        return MarketProfile(pointOfControl: pocPrice, valueAreaHigh: vah, valueAreaLow: val,
                             insideValueArea: inside, positionLabel: label)
    }

    static func profileReport(_ md: MarketData, symbol: String) -> String {
        guard let p = marketProfile(md) else { return "Need at least 20 candles for a market profile." }
        return """
        ## Market Profile — \(symbol)

        | Level | Price |
        |---|---|
        | Value Area High | \(fmt(p.valueAreaHigh, 5)) |
        | Point of Control | \(fmt(p.pointOfControl, 5)) |
        | Value Area Low | \(fmt(p.valueAreaLow, 5)) |

        Current price is **\(p.positionLabel)**. \
        Price above VAH with momentum favors continuation; re-entries into the value area often rotate back to the POC.
        """
    }

    // MARK: - 3. Liquidity Map (equal highs/lows, sweeps, stop hunts)

    struct LiquidityMap {
        let equalHighs: [Double]
        let equalLows: [Double]
        let sweptAbove: Bool      // recent sweep above equal highs (stop hunt up)
        let sweptBelow: Bool      // recent sweep below equal lows (stop hunt down)
        let nearestPoolAbove: Double?
        let nearestPoolBelow: Double?
    }

    static func liquidityMap(_ md: MarketData, tolerance: Double = 0.0008) -> LiquidityMap {
        let cs = Array(md.candles.suffix(90))
        guard cs.count >= 10 else {
            return LiquidityMap(equalHighs: [], equalLows: [], sweptAbove: false, sweptBelow: false, nearestPoolAbove: nil, nearestPoolBelow: nil)
        }
        let price = md.currentPrice > 0 ? md.currentPrice : (cs.last?.close ?? 0)
        // Swing highs/lows (2-bar fractals)
        var swingHighs: [Double] = []
        var swingLows: [Double] = []
        for i in 2..<(cs.count - 2) {
            if cs[i].high >= cs[i - 1].high, cs[i].high >= cs[i - 2].high, cs[i].high >= cs[i + 1].high, cs[i].high >= cs[i + 2].high {
                swingHighs.append(cs[i].high)
            }
            if cs[i].low <= cs[i - 1].low, cs[i].low <= cs[i - 2].low, cs[i].low <= cs[i + 1].low, cs[i].low <= cs[i + 2].low {
                swingLows.append(cs[i].low)
            }
        }
        // Cluster "equal" levels (resting liquidity).
        func clusterLevels(_ levels: [Double]) -> [Double] {
            var clusters: [[Double]] = []
            for l in levels.sorted() {
                if let last = clusters.last, let m = last.last, abs(l - m) / max(m, 1e-9) <= tolerance * 3 {
                    clusters[clusters.count - 1].append(l)
                } else {
                    clusters.append([l])
                }
            }
            return clusters.filter { $0.count >= 2 }.map { mean($0) }
        }
        let eqH = clusterLevels(swingHighs)
        let eqL = clusterLevels(swingLows)
        let last = cs.last!
        let prev = cs[cs.count - 2]
        let sweptAbove = eqH.contains { level in prev.high > level && last.close < level }
        let sweptBelow = eqL.contains { level in prev.low < level && last.close > level }
        let poolAbove = eqH.filter { $0 > price }.min()
        let poolBelow = eqL.filter { $0 < price }.max()
        return LiquidityMap(equalHighs: eqH, equalLows: eqL, sweptAbove: sweptAbove, sweptBelow: sweptBelow,
                            nearestPoolAbove: poolAbove, nearestPoolBelow: poolBelow)
    }

    static func liquidityReport(_ md: MarketData, symbol: String) -> String {
        let m = liquidityMap(md)
        var s = "## Liquidity Map — \(symbol)\n\n"
        s += "| Pool | Level |\n|---|---|\n"
        if let a = m.nearestPoolAbove { s += "| Buy-side liquidity (equal highs) | \(fmt(a, 5)) |\n" }
        if let b = m.nearestPoolBelow { s += "| Sell-side liquidity (equal lows) | \(fmt(b, 5)) |\n" }
        if m.nearestPoolAbove == nil && m.nearestPoolBelow == nil { s += "| — | no clustered pools nearby |\n" }
        s += "\n"
        if m.sweptAbove { s += "⚠️ **Stop-hunt sweep above equal highs** in the last bars — classic bull trap / reversal-down signature.\n" }
        if m.sweptBelow { s += "⚠️ **Stop-hunt sweep below equal lows** in the last bars — classic bear trap / reversal-up signature.\n" }
        if !m.sweptAbove && !m.sweptBelow { s += "No fresh sweeps. Price typically seeks the nearest resting pool before the real move.\n" }
        return s
    }

    // MARK: - 4. Range & Volatility Forecast (Parkinson / Garman-Klass / expected move)

    struct RangeForecast {
        let parkinsonVol: Double       // annualized-less, per-candle
        let garmanKlassVol: Double
        let expectedMove1: Double      // expected absolute move over next candle
        let expectedMove5: Double      // over next 5 candles
        let compression: Bool          // Bollinger squeeze style compression
        let expansionRisk: String
    }

    static func rangeForecast(_ md: MarketData) -> RangeForecast? {
        let cs = Array(md.candles.suffix(60))
        guard cs.count >= 20 else { return nil }
        let price = md.currentPrice > 0 ? md.currentPrice : (cs.last?.close ?? 0)
        // Parkinson (high-low)
        let park = sqrt(cs.reduce(0) { $0 + pow(log($1.high / max($1.low, 1e-9)), 2) } / (Double(cs.count) * 4 * log(2.0)))
        // Garman-Klass (OHLC)
        var gk = 0.0
        for c in cs {
            let hl = log(c.high / max(c.low, 1e-9))
            let co = log(c.close / max(c.open, 1e-9))
            gk += 0.5 * hl * hl - (2 * log(2.0) - 1) * co * co
        }
        gk = sqrt(max(gk / Double(cs.count), 0))
        let vol = (park + gk) / 2
        let move1 = price * vol
        // Compression: recent 10-candle range vs prior 50
        let recentRange = (cs.suffix(10).map { $0.high }.max() ?? 0) - (cs.suffix(10).map { $0.low }.min() ?? 0)
        let longRange = (cs.map { $0.high }.max() ?? 0) - (cs.map { $0.low }.min() ?? 0)
        let compression = longRange > 0 && recentRange / longRange < 0.22
        let risk: String
        switch vol * price {
        case let v where v > price * 0.004: risk = "high — size down, expect fast expansion"
        case let v where v > price * 0.0015: risk = "moderate"
        default: risk = "low — watch for squeeze release"
        }
        return RangeForecast(parkinsonVol: park, garmanKlassVol: gk,
                             expectedMove1: move1, expectedMove5: move1 * sqrt(5),
                             compression: compression, expansionRisk: risk)
    }

    static func rangeReport(_ md: MarketData, symbol: String) -> String {
        guard let f = rangeForecast(md) else { return "Need at least 20 candles for a range forecast." }
        return """
        ## Range & Volatility Forecast — \(symbol)

        | Metric | Value |
        |---|---|
        | Parkinson volatility (per candle) | \(pct(f.parkinsonVol)) |
        | Garman-Klass volatility | \(pct(f.garmanKlassVol)) |
        | Expected move — next candle | ±\(fmt(f.expectedMove1, 5)) |
        | Expected move — next 5 candles | ±\(fmt(f.expectedMove5, 5)) |
        | Compression (squeeze) | \(f.compression ? "yes — expansion likely" : "no") |

        Expansion risk: **\(f.expansionRisk)**. Use the expected move to sanity-check stop and target distances.
        """
    }

    // MARK: - 5. Entropy & Trend Quality (Shannon entropy, Kaufman ER, fractal dimension)

    struct EntropyReport {
        let shannonEntropy: Double     // bits — higher = more random
        let maxEntropy: Double
        let efficiencyRatio: Double    // 0...1 — higher = cleaner trend
        let fractalDimension: Double   // 1 (smooth trend) ... 2 (max roughness)
        let trendQuality: String
    }

    static func entropyAnalysis(_ prices: [Double]) -> EntropyReport? {
        guard prices.count >= 40 else { return nil }
        let window = Array(prices.suffix(120))
        let rets = zip(window, window.dropFirst()).compactMap { o, n -> Double? in
            (o > 0 && n > 0) ? log(n / o) : nil
        }
        guard rets.count >= 30 else { return nil }
        // Shannon entropy of sign runs discretized into 4 bins by magnitude.
        let absRets = rets.map { abs($0) }.sorted()
        let q1 = absRets[absRets.count / 4], q2 = absRets[absRets.count / 2], q3 = absRets[absRets.count * 3 / 4]
        var bins = [Double](repeating: 0, count: 8) // 4 magnitude levels × 2 signs
        for r in rets {
            let a = abs(r)
            let mag = a <= q1 ? 0 : a <= q2 ? 1 : a <= q3 ? 2 : 3
            bins[r < 0 ? mag : mag + 4] += 1
        }
        let total = Double(rets.count)
        var entropy = 0.0
        for b in bins where b > 0 {
            let p = b / total
            entropy -= p * log2(p)
        }
        let maxE = log2(8.0)
        // Kaufman Efficiency Ratio over 20 periods.
        let n = min(20, window.count - 1)
        let change = abs(window.last! - window[window.count - 1 - n])
        var path = 0.0
        for i in (window.count - 1 - n)..<(window.count - 1) { path += abs(window[i + 1] - window[i]) }
        let er = path > 0 ? change / path : 0
        // Fractal dimension (Higuchi-lite, kmax 8).
        let fd = higuchiFD(window, kmax: 8)
        let quality: String
        if er > 0.55 && entropy < maxE * 0.85 { quality = "clean, tradeable trend" }
        else if er > 0.35 { quality = "mixed — trend with noise" }
        else { quality = "choppy / mean-reverting — fade extremes only" }
        return EntropyReport(shannonEntropy: entropy, maxEntropy: maxE, efficiencyRatio: er,
                             fractalDimension: fd, trendQuality: quality)
    }

    private static func higuchiFD(_ x: [Double], kmax: Int) -> Double {
        let n = x.count
        guard n > kmax * 2 else { return 1.5 }
        var logL: [Double] = []
        var logK: [Double] = []
        for k in 1...kmax {
            var L = 0.0
            for m in 0..<k {
                var sum = 0.0
                var count = 0
                var i = m
                while i + k < n {
                    sum += abs(x[i + k] - x[i])
                    count += 1
                    i += k
                }
                if count > 0 {
                    let norm = Double(n - 1) / (Double(count) * Double(k) * Double(k))
                    L += sum * norm
                }
            }
            L /= Double(k)
            if L > 0 { logL.append(log(L)); logK.append(log(1.0 / Double(k))) }
        }
        guard logL.count > 2 else { return 1.5 }
        let r = AdvancedBackend.linearRegression(logL)
        return clamp(r.slope, 1.0, 2.0)
    }

    static func entropyReport(_ md: MarketData, symbol: String) -> String {
        guard let e = entropyAnalysis(md.closes) else { return "Need at least 40 candles for entropy analysis." }
        return """
        ## Entropy & Trend Quality — \(symbol)

        | Metric | Value | Reading |
        |---|---|---|
        | Shannon entropy | \(fmt(e.shannonEntropy, 2)) / \(fmt(e.maxEntropy, 2)) bits | \(e.shannonEntropy < e.maxEntropy * 0.8 ? "structured" : "noisy") |
        | Kaufman efficiency ratio | \(fmt(e.efficiencyRatio, 2)) | \(e.efficiencyRatio > 0.5 ? "directional" : e.efficiencyRatio > 0.3 ? "mixed" : "choppy") |
        | Fractal dimension | \(fmt(e.fractalDimension, 2)) | \(e.fractalDimension < 1.4 ? "smooth" : e.fractalDimension < 1.6 ? "normal" : "rough") |

        Verdict: **\(e.trendQuality)**.
        """
    }

    // MARK: - 6. Regime Switching (Markov-lite bull/bear/range probabilities)

    struct RegimeState {
        let bull: Double
        let bear: Double
        let range: Double
        let dominant: String
        let persistence: Double   // how sticky the current regime is
    }

    static func regimeSwitch(_ prices: [Double]) -> RegimeState? {
        guard prices.count >= 50 else { return nil }
        let rets = zip(prices, prices.dropFirst()).compactMap { o, n -> Double? in (o > 0 && n > 0) ? log(n / o) : nil }
        guard rets.count >= 40 else { return nil }
        // Classify each of the last 40 returns with rolling 10-bar stats, then Markov smooth.
        var states: [Int] = [] // 1 bull, 0 range, -1 bear
        for i in 10..<rets.count {
            let w = Array(rets[(i - 10)..<i])
            let m = mean(w), s = sd(w)
            if s == 0 { states.append(0); continue }
            let t = m / s
            states.append(t > 0.35 ? 1 : t < -0.35 ? -1 : 0)
        }
        guard let lastState = states.last else { return nil }
        // Transition matrix for persistence.
        var stay = 0, moves = 0
        for i in 1..<states.count {
            if states[i] == states[i - 1] { stay += 1 } else { moves += 1 }
        }
        let persistence = (stay + moves) > 0 ? Double(stay) / Double(stay + moves) : 0.5
        // Current probabilities = recent state histogram weighted by recency.
        var bull = 0.0, bear = 0.0, range = 0.0, wsum = 0.0
        for (i, st) in states.enumerated() {
            let w = 1.0 + Double(i) / Double(states.count) // recency weighting
            wsum += w
            if st == 1 { bull += w } else if st == -1 { bear += w } else { range += w }
        }
        let dominant = bull >= bear && bull >= range ? "bull trend" : bear >= bull && bear >= range ? "bear trend" : "range / balance"
        return RegimeState(bull: bull / wsum, bear: bear / wsum, range: range / wsum,
                           dominant: dominant, persistence: persistence)
    }

    // MARK: - 7. Tick Speed / Micro-velocity (from live price series)

    struct SpeedReport {
        let ticksPerMinute: Double
        let velocity: Double      // signed, in bps of price per minute
        let acceleration: Double
        let reading: String
    }

    static func tickSpeed(_ prices: [Double], perSeconds: Double = 2.0) -> SpeedReport? {
        guard prices.count >= 20, let last = prices.last, let first = prices.first, last > 0, first > 0 else { return nil }
        let minutes = Double(prices.count) * perSeconds / 60.0
        let velocity = (last / first - 1) * 10_000 / max(minutes, 0.01) // bps per minute
        let half = prices.count / 2
        let v1 = (prices[half] / first - 1) * 10_000
        let v2 = (last / prices[half] - 1) * 10_000
        let accel = (v2 - v1) / max(minutes, 0.01)
        let reading: String
        if abs(velocity) > 8 { reading = velocity > 0 ? "aggressive buying pace" : "aggressive selling pace" }
        else if abs(velocity) > 3 { reading = velocity > 0 ? "steady buying" : "steady selling" }
        else { reading = "balanced tape" }
        return SpeedReport(ticksPerMinute: Double(prices.count) / max(minutes, 0.01),
                           velocity: velocity, acceleration: accel, reading: reading)
    }

    // MARK: - 8. Master Confluence Scorecard (everything merged)

    struct ScorecardEntry: Identifiable {
        let id = UUID()
        let engine: String
        let score: Double       // -1...1
        let confidence: Double  // 0...1
        let note: String
    }

    struct MasterConfluence {
        let entries: [ScorecardEntry]
        let totalScore: Double      // -1...1 weighted
        let totalConfidence: Double // 0...1
        let verdict: Direction
        let summary: String
    }

    /// Run EVERY available backend engine over the same market data and merge into one
    /// weighted confluence score. This is the app's deepest per-symbol audit.
    static func masterConfluence(_ md: MarketData, engine: SignalEngine? = nil) -> MasterConfluence {
        var entries: [ScorecardEntry] = []
        let closes = md.closes

        // 1. Council vote blend (all agents incl. APEX agents)
        if let engine {
            let ind = engine.analyzer.analyze(md)
            let votes = engine.agents.filter { $0.isActive }.map { $0.analyze(md, ind) }
            let (score, conf, _) = MetaOrchestrator.blend(votes: votes, symbol: md.symbol, timeframe: md.timeframe)
            entries.append(ScorecardEntry(engine: "Agent Council (\(votes.count) agents)", score: clamp(score, -1, 1), confidence: conf, note: "\(votes.filter { $0.direction.isBullish }.count) bullish / \(votes.filter { $0.direction.isBearish }.count) bearish"))
        }

        // 2. Patterns
        let patterns = candlePatterns(md).suffix(10)
        if !patterns.isEmpty {
            let bull = patterns.filter { $0.bullish }.map { $0.strength }.reduce(0, +)
            let bear = patterns.filter { !$0.bullish }.map { $0.strength }.reduce(0, +)
            let sc = clamp((bull - bear) / max(bull + bear, 0.01), -1, 1)
            entries.append(ScorecardEntry(engine: "Candlestick Patterns", score: sc, confidence: clamp((bull + bear) / 4, 0.25, 0.85), note: "\(patterns.count) recent patterns"))
        }

        // 3. Market profile position
        if let p = marketProfile(md) {
            let price = md.currentPrice > 0 ? md.currentPrice : (closes.last ?? 0)
            let sc: Double = price > p.valueAreaHigh ? 0.5 : price < p.valueAreaLow ? -0.5 : (price > p.pointOfControl ? 0.15 : -0.15)
            entries.append(ScorecardEntry(engine: "Market Profile", score: sc, confidence: 0.55, note: p.positionLabel))
        }

        // 4. Liquidity sweeps
        let liq = liquidityMap(md)
        if liq.sweptBelow { entries.append(ScorecardEntry(engine: "Liquidity", score: 0.65, confidence: 0.7, note: "sell-side swept → reversal up")) }
        else if liq.sweptAbove { entries.append(ScorecardEntry(engine: "Liquidity", score: -0.65, confidence: 0.7, note: "buy-side swept → reversal down")) }
        else if let above = liq.nearestPoolAbove, let below = liq.nearestPoolBelow {
            let price = md.currentPrice > 0 ? md.currentPrice : (closes.last ?? 0)
            let sc = (above - price) < (price - below) ? 0.2 : -0.2
            entries.append(ScorecardEntry(engine: "Liquidity", score: sc, confidence: 0.45, note: "nearest pool \(sc > 0 ? "above" : "below")"))
        }

        // 5. Entropy / trend quality
        if let e = entropyAnalysis(closes) {
            let trendDir = (closes.last ?? 0) > (closes.count > 21 ? closes[closes.count - 21] : closes.first ?? 0) ? 1.0 : -1.0
            let sc = trendDir * e.efficiencyRatio
            entries.append(ScorecardEntry(engine: "Entropy / Efficiency", score: clamp(sc, -1, 1), confidence: clamp(e.efficiencyRatio + 0.2, 0, 0.9), note: e.trendQuality))
        }

        // 6. Regime switching
        if let r = regimeSwitch(closes) {
            let sc = r.bull - r.bear
            entries.append(ScorecardEntry(engine: "Regime Switch", score: clamp(sc, -1, 1), confidence: clamp(r.persistence, 0.3, 0.9), note: "\(r.dominant) · \(pct(r.persistence)) sticky"))
        }

        // 7. Volatility regime (existing engines as advisory context)
        let garch = AdvancedBackend.garchLiteVolatility(closes)
        if garch.current > 0 {
            entries.append(ScorecardEntry(engine: "Volatility State", score: 0, confidence: 0.5, note: garch.regime))
        }

        // 8. Kalman trend (existing)
        let kal = AdvancedBackend.kalman(closes)
        if let last = closes.last, kal.estimate > 0 {
            let sc = clamp((kal.estimate / last - 1) * 40, -1, 1)
            entries.append(ScorecardEntry(engine: "Kalman Fair Value", score: sc, confidence: clamp(1 - kal.uncertainty * 20, 0.2, 0.8), note: "fair \(fmt(kal.estimate, 5))"))
        }

        // 9. Tick speed (live series)
        if let sp = tickSpeed(closes, perSeconds: 60) {
            entries.append(ScorecardEntry(engine: "Tape Speed", score: clamp(sp.velocity / 12, -1, 1), confidence: 0.5, note: sp.reading))
        }

        // Weighted merge.
        var wsum = 0.0, acc = 0.0, csum = 0.0
        for e in entries {
            let w = e.confidence
            wsum += w
            acc += e.score * w
            csum += e.confidence * w
        }
        let total = wsum > 0 ? acc / wsum : 0
        let conf = wsum > 0 ? csum / wsum : 0
        let verdict: Direction
        switch total {
        case let t where t >= 0.45: verdict = .strongBullish
        case let t where t >= 0.15: verdict = .bullish
        case let t where t <= -0.45: verdict = .strongBearish
        case let t where t <= -0.15: verdict = .bearish
        default: verdict = .neutral
        }
        let agree = entries.filter { ($0.score > 0.15) == (total > 0.15) && abs($0.score) > 0.05 }.count
        let summary = "\(agree)/\(entries.count) engines align with the \(dirLabel(verdict).lowercased()) verdict."
        return MasterConfluence(entries: entries, totalScore: total, totalConfidence: conf, verdict: verdict, summary: summary)
    }

    static func masterReport(_ md: MarketData, symbol: String, engine: SignalEngine? = nil) -> String {
        let mc = masterConfluence(md, engine: engine)
        var s = "## Master Confluence — \(symbol)\n\n"
        s += "**Verdict: \(dirLabel(mc.verdict))** · score \(fmt(mc.totalScore, 2)) (−1…+1) · confidence \(pct(mc.totalConfidence))\n\n"
        s += "| Engine | Score | Conf | Note |\n|---|---|---|---|\n"
        for e in mc.entries {
            s += "| \(e.engine) | \(fmt(e.score, 2)) | \(pct(e.confidence)) | \(e.note) |\n"
        }
        s += "\n\(mc.summary)\n"
        return s
    }

    // MARK: - 9. Multi-Symbol Scanner

    struct ScanHit: Identifiable {
        let id = UUID()
        let symbol: String
        let score: Double
        let verdict: Direction
        let confidence: Double
        let note: String
    }

    /// Rank a set of symbols by master confluence. `data` provides cached candles per symbol.
    static func scan(symbols: [String], data: (String) -> MarketData?) -> [ScanHit] {
        var hits: [ScanHit] = []
        for sym in symbols {
            guard let md = data(sym) else { continue }
            let mc = masterConfluence(md)
            guard abs(mc.totalScore) > 0.05 else { continue }
            hits.append(ScanHit(symbol: sym, score: mc.totalScore, verdict: mc.verdict,
                                confidence: mc.totalConfidence, note: mc.summary))
        }
        return hits.sorted { abs($0.score) > abs($1.score) }
    }
}
