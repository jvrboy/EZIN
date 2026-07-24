import Foundation

/// PatternRecognition — on-device chart pattern detection engine for EZIN.
///
/// Detects advanced technical patterns beyond basic candlestick patterns:
///   - Chart patterns: flags, pennants, wedges, triangles, channels
///   - Reversal patterns: head and shoulders, double/top bottom, triple top/bottom
///   - Volume patterns: climax, divergence, confirmation
///   - Smart support/resistance from volume clustering and swing points
///
/// All outputs are deterministic, advisory indicators — not trade signals.
enum PatternRecognition {

    // MARK: - Pattern Data Structures

    /// A detected technical pattern with metadata.
    struct ChartPattern: Identifiable {
        let id = UUID()
        let name: String
        let type: PatternType
        let direction: Direction          // pattern's implied direction
        let startIndex: Int
        let endIndex: Int
        let startPrice: Double
        let endPrice: Double
        let confidence: Double            // 0...1
        let description: String
    }

    enum PatternType: String, CaseIterable {
        case flag = "Flag"
        case pennant = "Pennant"
        case wedge = "Wedge"
        case ascendingTriangle = "Ascending Triangle"
        case descendingTriangle = "Descending Triangle"
        case symmetricalTriangle = "Symmetrical Triangle"
        case channel = "Channel"
        case headAndShoulders = "Head & Shoulders"
        case inverseHeadAndShoulders = "Inverse Head & Shoulders"
        case doubleTop = "Double Top"
        case doubleBottom = "Double Bottom"
        case tripleTop = "Triple Top"
        case tripleBottom = "Triple Bottom"
        case roundingTop = "Rounding Top"
        case roundingBottom = "Rounding Bottom"

        var isReversal: Bool {
            switch self {
            case .headAndShoulders, .inverseHeadAndShoulders, .doubleTop, .doubleBottom,
                    .tripleTop, .tripleBottom, .roundingTop, .roundingBottom:
                return true
            default: return false
            }
        }

        var isContinuation: Bool { !isReversal }
    }

    /// Support/resistance level from volume clustering or swing points.
    struct SRL {
        let price: Double
        let type: SRType
        let strength: Double          // 0...1
        let touches: Int
        let description: String
    }

    enum SRType: String {
        case support = "Support"
        case resistance = "Resistance"
        case both = "Support/Resistance"
    }

    /// Volume pattern detected.
    struct VolumePattern: Identifiable {
        let id = UUID()
        let name: String
        let bullish: Bool
        let confidence: Double
        let index: Int
        let description: String
    }

    // MARK: - Chart Pattern Detection

    /// Run all pattern detectors and return the most significant patterns.
    static func detectAllPatterns(candles: [Candle], lookback: Int = 120) -> [ChartPattern] {
        guard candles.count >= 60 else { return [] }
        let recent = Array(candles.suffix(min(lookback, candles.count)))
        var patterns: [ChartPattern] = []

        // Find swing points first
        let swings = findSwingPoints(candles: recent)

        // Detect each pattern type
        patterns.append(contentsOf: detectFlags(candles: recent, swings: swings))
        patterns.append(contentsOf: detectTriangles(candles: recent, swings: swings))
        patterns.append(contentsOf: detectHeadAndShoulders(candles: recent, swings: swings))
        patterns.append(contentsOf: detectDoubleTopsBottoms(candles: recent, swings: swings))
        patterns.append(contentsOf: detectChannels(candles: recent, swings: swings))
        patterns.append(contentsOf: detectWedges(candles: recent, swings: swings))
        patterns.append(contentsOf: detectRoundingTopsBottoms(candles: recent, swings: swings))
        patterns.append(contentsOf: detectPennants(candles: recent, swings: swings))

        // Filter to high-confidence only, sorted by confidence
        return patterns.filter { $0.confidence >= 0.4 }.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Swing Point Detection

    struct SwingPoint {
        let index: Int
        let price: Double
        let isHigh: Bool
        let strength: Double  // 0...1 based on prominence
    }

    static func findSwingPoints(candles: [Candle], leftBars: Int = 3, rightBars: Int = 3) -> [SwingPoint] {
        guard candles.count > leftBars + rightBars else { return [] }
        let highs = candles.map { $0.high }
        let lows = candles.map { $0.low }
        var swings: [SwingPoint] = []

        for i in leftBars..<(candles.count - rightBars) {
            // Swing high
            var isHigh = true
            for j in (i - leftBars)...(i + rightBars) where j != i {
                if highs[j] >= highs[i] { isHigh = false; break }
            }
            if isHigh {
                let localRange = averageRange(candles: Array(candles[max(0, i - 10)...min(candles.count - 1, i + 10)]))
                let prominence = localRange > 0 ? (highs[i] - lows[i]) / localRange : 0.5
                swings.append(SwingPoint(index: i, price: highs[i], isHigh: true, strength: min(prominence, 1.0)))
            }

            // Swing low
            var isLow = true
            for j in (i - leftBars)...(i + rightBars) where j != i {
                if lows[j] <= lows[i] { isLow = false; break }
            }
            if isLow {
                let localRange = averageRange(candles: Array(candles[max(0, i - 10)...min(candles.count - 1, i + 10)]))
                let prominence = localRange > 0 ? (highs[i] - lows[i]) / localRange : 0.5
                swings.append(SwingPoint(index: i, price: lows[i], isHigh: false, strength: min(prominence, 1.0)))
            }
        }
        return swings
    }

    // MARK: - Flag Detection

    /// Flag: sharp price move (pole) followed by a shallow rectangular consolidation.
    private static func detectFlags(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 6 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 4..<swings.count {
            let recent = Array(swings[(i - 4)...i])
            let highs = recent.filter { $0.isHigh }.map { $0.price }
            let lows = recent.filter { !$0.isHigh }.map { $0.price }
            guard highs.count >= 2, lows.count >= 2 else { continue }

            let highTrend = linearSlope(highs)
            let lowTrend = linearSlope(lows)
            let isFlat = abs(highTrend) < 0.002 && abs(lowTrend) < 0.002
            let isContrary = (highTrend > 0) == (lowTrend > 0) // parallel drift

            // Pole: strong move before the consolidation
            let poleStart = swings[max(0, i - 6)].price
            let poleEnd = recent.first!.price
            let poleMove = abs(poleEnd - poleStart) / max(poleStart, 0.000001)
            guard poleMove > 0.02 else { continue }

            if isFlat && isContrary && poleMove > 0.02 {
                let direction: Direction = (poleEnd > poleStart) ? .bullish : .bearish
                let conf = min(0.5 + poleMove * 3, 0.85)
                patterns.append(ChartPattern(
                    name: "Flag", type: .flag, direction: direction,
                    startIndex: swings[max(0, i - 6)].index,
                    endIndex: recent.last!.index,
                    startPrice: poleStart, endPrice: recent.last!.price,
                    confidence: conf,
                    description: "\(direction.isBullish ? "Bullish" : "Bearish") flag: sharp \(fmt(poleMove * 100))% move followed by shallow consolidation"
                ))
            }
        }
        return patterns
    }

    // MARK: - Pennant Detection

    /// Pennant: small symmetrical triangle after a sharp move.
    private static func detectPennants(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 6 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 4..<swings.count {
            let recent = Array(swings[(i - 4)...i])
            let highs = recent.filter { $0.isHigh }.map { $0.price }
            let lows = recent.filter { !$0.isHigh }.map { $0.price }
            guard highs.count >= 2, lows.count >= 2 else { continue }

            let highSlope = linearSlope(highs)
            let lowSlope = linearSlope(lows)
            let converging = highSlope < 0 && lowSlope > 0  // converging lines (triangle)
            let narrowPct = abs(highs.last! - lows.last!) / max(highs.first! - lows.first!, 0.000001)
            let narrowEnough = narrowPct < 0.7  // at least 30% narrowing

            let poleStart = swings[max(0, i - 6)].price
            let poleEnd = recent.first!.price
            let poleMove = abs(poleEnd - poleStart) / max(poleStart, 0.000001)

            if converging && narrowEnough && poleMove > 0.02 {
                let direction: Direction = (poleEnd > poleStart) ? .bullish : .bearish
                patterns.append(ChartPattern(
                    name: "Pennant", type: .pennant, direction: direction,
                    startIndex: swings[max(0, i - 6)].index,
                    endIndex: recent.last!.index,
                    startPrice: poleStart, endPrice: recent.last!.price,
                    confidence: 0.6,
                    description: "\(direction.isBullish ? "Bullish" : "Bearish") pennant: sharp move followed by symmetrical consolidation"
                ))
            }
        }
        return patterns
    }

    // MARK: - Triangle Detection

    private static func detectTriangles(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 6 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 4..<swings.count {
            let recent = Array(swings[(i - 4)...i])
            let highs = recent.filter { $0.isHigh }.map { $0.price }
            let lows = recent.filter { !$0.isHigh }.map { $0.price }
            guard highs.count >= 2, lows.count >= 2 else { continue }

            let highSlope = linearSlope(highs)
            let lowSlope = linearSlope(lows)

            // Ascending triangle: flat resistance, rising support
            if abs(highSlope) < 0.001 && lowSlope > 0.001 {
                let conf = min(0.5 + abs(lowSlope) * 50, 0.8)
                patterns.append(ChartPattern(
                    name: "Ascending Triangle", type: .ascendingTriangle, direction: .bullish,
                    startIndex: recent.first!.index, endIndex: recent.last!.index,
                    startPrice: highs.first!, endPrice: highs.last!,
                    confidence: conf,
                    description: "Ascending triangle: flat resistance at \(fmt(highs.last!)) with rising support — bullish breakout expected"
                ))
            }

            // Descending triangle: flat support, falling resistance
            if abs(lowSlope) < 0.001 && highSlope < -0.001 {
                let conf = min(0.5 + abs(highSlope) * 50, 0.8)
                patterns.append(ChartPattern(
                    name: "Descending Triangle", type: .descendingTriangle, direction: .bearish,
                    startIndex: recent.first!.index, endIndex: recent.last!.index,
                    startPrice: lows.first!, endPrice: lows.last!,
                    confidence: conf,
                    description: "Descending triangle: flat support at \(fmt(lows.last!)) with falling resistance — bearish breakdown expected"
                ))
            }

            // Symmetrical triangle: converging lines
            if highSlope < -0.001 && lowSlope > 0.001 {
                let conf = min(0.5 + (abs(highSlope) + abs(lowSlope)) * 30, 0.75)
                let narrowPct = abs(highs.last! - lows.last!) / max(abs(highs.first! - lows.first!), 0.000001)
                if narrowPct < 0.75 {
                    patterns.append(ChartPattern(
                        name: "Symmetrical Triangle", type: .symmetricalTriangle, direction: .neutral,
                        startIndex: recent.first!.index, endIndex: recent.last!.index,
                        startPrice: (highs.first! + lows.first!) / 2,
                        endPrice: (highs.last! + lows.last!) / 2,
                        confidence: conf,
                        description: "Symmetrical triangle: converging swing points — breakout direction is unclear"
                    ))
                }
            }
        }
        return patterns
    }

    // MARK: - Wedge Detection

    private static func detectWedges(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 6 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 4..<swings.count {
            let recent = Array(swings[(i - 4)...i])
            let highs = recent.filter { $0.isHigh }.map { $0.price }
            let lows = recent.filter { !$0.isHigh }.map { $0.price }
            guard highs.count >= 2, lows.count >= 2 else { continue }

            let highSlope = linearSlope(highs)
            let lowSlope = linearSlope(lows)
            let bothDown = highSlope < -0.001 && lowSlope < -0.001
            let bothUp = highSlope > 0.001 && lowSlope > 0.001
            let converging = abs(highSlope) > abs(lowSlope) || abs(lowSlope) > abs(highSlope)
            guard (bothDown || bothUp) && converging else { continue }

            if bothUp {
                // Rising wedge (bearish)
                patterns.append(ChartPattern(
                    name: "Rising Wedge", type: .wedge, direction: .bearish,
                    startIndex: recent.first!.index, endIndex: recent.last!.index,
                    startPrice: lows.first!, endPrice: highs.last!,
                    confidence: 0.6,
                    description: "Rising wedge: higher highs and higher lows with narrowing range — bearish reversal pattern"
                ))
            } else if bothDown {
                // Falling wedge (bullish)
                patterns.append(ChartPattern(
                    name: "Falling Wedge", type: .wedge, direction: .bullish,
                    startIndex: recent.first!.index, endIndex: recent.last!.index,
                    startPrice: highs.first!, endPrice: lows.last!,
                    confidence: 0.6,
                    description: "Falling wedge: lower highs and lower lows with narrowing range — bullish reversal pattern"
                ))
            }
        }
        return patterns
    }

    // MARK: - Channel Detection

    private static func detectChannels(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 8 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 6..<swings.count {
            let recent = Array(swings[(i - 6)...i])
            let highs = recent.filter { $0.isHigh }.map { $0.price }
            let lows = recent.filter { !$0.isHigh }.map { $0.price }
            guard highs.count >= 3, lows.count >= 3 else { continue }

            let highSlope = linearSlope(highs)
            let lowSlope = linearSlope(lows)
            let parallel = abs(highSlope - lowSlope) < max(abs(highSlope), abs(lowSlope)) * 0.3

            if parallel && abs(highSlope) > 0.0005 {
                let direction: Direction = highSlope > 0 ? .bullish : .bearish
                let channelWidth = abs(highs.last! - lows.last!) / highs.last!
                patterns.append(ChartPattern(
                    name: "Channel", type: .channel, direction: direction,
                    startIndex: recent.first!.index, endIndex: recent.last!.index,
                    startPrice: lows.first!, endPrice: highs.last!,
                    confidence: min(0.5 + channelWidth * 5, 0.8),
                    description: "\(direction.isBullish ? "Rising" : "Falling") channel: parallel trend lines (\(fmt(channelWidth * 100))% wide)"
                ))
            }
        }
        return patterns
    }

    // MARK: - Head & Shoulders Detection

    private static func detectHeadAndShoulders(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 7 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 5..<swings.count {
            let recent = Array(swings[(i - 5)...i])
            let highs = recent.filter { $0.isHigh }.map { $0 }
            guard highs.count >= 3 else { continue }

            // Need 3 swing highs: left shoulder, head, right shoulder
            for j in 0..<(highs.count - 2) {
                let left = highs[j]
                let head = highs[j + 1]
                let right = highs[j + 2]

                // Head must be highest, shoulders approximately equal
                if head.price > left.price && head.price > right.price {
                    let shoulderAvg = (left.price + right.price) / 2
                    let neckline = shoulderAvg
                    let heightPct = (head.price - neckline) / head.price

                    // Shoulders within 5% of each other
                    let shoulderDiff = abs(left.price - right.price) / max(left.price, right.price)
                    if heightPct > 0.02 && shoulderDiff < 0.05 {
                        // Check volume pattern (optional enhancement)
                        let pattern = ChartPattern(
                            name: "Head & Shoulders", type: .headAndShoulders, direction: .bearish,
                            startIndex: left.index, endIndex: right.index,
                            startPrice: left.price, endPrice: right.price,
                            confidence: min(0.5 + heightPct * 5, 0.9),
                            description: "Head & shoulders: head at \(fmt(head.price)), neckline at \(fmt(neckline)), height \(fmt(heightPct * 100))% — bearish reversal"
                        )
                        patterns.append(pattern)
                    }
                }

                // Inverse H&S
                if head.price < left.price && head.price < right.price {
                    let shoulderAvg = (left.price + right.price) / 2
                    let neckline = shoulderAvg
                    let heightPct = (neckline - head.price) / head.price
                    let shoulderDiff = abs(left.price - right.price) / max(left.price, right.price)

                    if heightPct > 0.02 && shoulderDiff < 0.05 {
                        patterns.append(ChartPattern(
                            name: "Inverse Head & Shoulders", type: .inverseHeadAndShoulders, direction: .bullish,
                            startIndex: left.index, endIndex: right.index,
                            startPrice: left.price, endPrice: right.price,
                            confidence: min(0.5 + heightPct * 5, 0.9),
                            description: "Inverse H&S: head at \(fmt(head.price)), neckline at \(fmt(neckline)), height \(fmt(heightPct * 100))% — bullish reversal"
                        ))
                    }
                }
            }
        }
        return patterns
    }

    // MARK: - Double Top / Bottom Detection

    private static func detectDoubleTopsBottoms(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard swings.count >= 6 else { return [] }
        var patterns: [ChartPattern] = []

        for i in 3..<swings.count {
            let recent = Array(swings[(i - 3)...i])
            let highs = recent.filter { $0.isHigh }
            let lows = recent.filter { !$0.isHigh }

            // Double top: two similar highs with a valley between
            if highs.count >= 2 {
                let h1 = highs[highs.count - 2]
                let h2 = highs.last!
                let diff = abs(h1.price - h2.price) / max(h1.price, h2.price)

                if diff < 0.03 {
                    let valley = lows.filter { $0.index > h1.index && $0.index < h2.index }.min { $0.price < $1.price }
                    if let valley = valley {
                        let heightPct = (h1.price - valley.price) / h1.price
                        if heightPct > 0.02 {
                            patterns.append(ChartPattern(
                                name: "Double Top", type: .doubleTop, direction: .bearish,
                                startIndex: h1.index, endIndex: h2.index,
                                startPrice: h1.price, endPrice: h2.price,
                                confidence: min(0.5 + heightPct * 3, 0.85),
                                description: "Double top at \(fmt(h1.price)) and \(fmt(h2.price)) with valley at \(fmt(valley.price)) — bearish reversal"
                            ))
                        }
                    }
                }
            }

            // Double bottom: two similar lows with a peak between
            if lows.count >= 2 {
                let l1 = lows[lows.count - 2]
                let l2 = lows.last!
                let diff = abs(l1.price - l2.price) / max(l1.price, l2.price)

                if diff < 0.03 {
                    let peak = highs.filter { $0.index > l1.index && $0.index < l2.index }.max { $0.price < $1.price }
                    if let peak = peak {
                        let heightPct = (peak.price - l1.price) / l1.price
                        if heightPct > 0.02 {
                            patterns.append(ChartPattern(
                                name: "Double Bottom", type: .doubleBottom, direction: .bullish,
                                startIndex: l1.index, endIndex: l2.index,
                                startPrice: l1.price, endPrice: l2.price,
                                confidence: min(0.5 + heightPct * 3, 0.85),
                                description: "Double bottom at \(fmt(l1.price)) and \(fmt(l2.price)) with peak at \(fmt(peak.price)) — bullish reversal"
                            ))
                        }
                    }
                }
            }
        }
        return patterns
    }

    // MARK: - Rounding Top / Bottom Detection

    private static func detectRoundingTopsBottoms(candles: [Candle], swings: [SwingPoint]) -> [ChartPattern] {
        guard candles.count >= 60 else { return [] }
        var patterns: [ChartPattern] = []

        // Look for a gradual curve in the last 40 candles
        let lookback = min(40, candles.count / 2)
        let recent = Array(candles.suffix(lookback))
        let closes = recent.map { $0.close }

        // Fit a quadratic curve to detect rounding
        let n = closes.count
        guard n > 10 else { return [] }
        let xs = (0..<n).map { Double($0) - Double(n) / 2 }
        let mid = Double(n) / 2

        // Linear regression first
        let sx = xs.reduce(0, +)
        let sy = closes.reduce(0, +)
        let sxx = xs.reduce(0) { $0 + $1 * $1 }
        let sxy = zip(xs, closes).reduce(0) { $0 + $1.0 * $1.1 }
        let slope = (sxx - sx * sx / Double(n)) > 0
            ? (sxy - sx * sy / Double(n)) / (sxx - sx * sx / Double(n))
            : 0

        // Quadratic coefficient by fitting second difference
        var quadSum = 0.0
        for i in 2..<n {
            quadSum += (closes[i] - 2 * closes[i - 1] + closes[i - 2])
        }
        let quadCoeff = quadSum / Double(n - 2)

        // If quadratic coefficient is significant, we have rounding
        let priceLevel = closes.last ?? closes.first ?? 1
        let relativeQuad = abs(quadCoeff) / max(priceLevel, 0.000001)

        if relativeQuad > 0.0005 {
            if quadCoeff < 0 && slope > -0.0001 {
                // Rounding top (concave down)
                let startPrice = closes.first ?? 0
                let endPrice = closes.last ?? 0
                let heightPct = (recent.map { $0.high }.max()! - startPrice) / startPrice
                patterns.append(ChartPattern(
                    name: "Rounding Top", type: .roundingTop, direction: .bearish,
                    startIndex: recent.first!.timestamp.timeIntervalSince1970 > 0 ? 0 : 0,
                    endIndex: recent.count - 1,
                    startPrice: startPrice, endPrice: endPrice,
                    confidence: min(0.5 + relativeQuad * 500, 0.8),
                    description: "Rounding top detected (quadratic coefficient \(fmt(quadCoeff)) — bearish reversal"
                ))
            } else if quadCoeff > 0 && slope < 0.0001 {
                // Rounding bottom (concave up)
                let startPrice = closes.first ?? 0
                let endPrice = closes.last ?? 0
                patterns.append(ChartPattern(
                    name: "Rounding Bottom", type: .roundingBottom, direction: .bullish,
                    startIndex: 0, endIndex: recent.count - 1,
                    startPrice: startPrice, endPrice: endPrice,
                    confidence: min(0.5 + relativeQuad * 500, 0.8),
                    description: "Rounding bottom detected (quadratic coefficient \(fmt(quadCoeff)) — bullish reversal"
                ))
            }
        }

        return patterns
    }

    // MARK: - Support & Resistance Detection

    /// Detect support and resistance levels from swing points and volume clustering.
    static func detectSupportResistance(
        candles: [Candle],
        lookback: Int = 120,
        minTouches: Int = 2,
        clusterTolerance: Double = 0.003
    ) -> [SRL] {
        guard candles.count >= 30 else { return [] }
        let recent = Array(candles.suffix(min(lookback, candles.count)))
        let swings = findSwingPoints(candles: recent, leftBars: 3, rightBars: 3)

        // Cluster swing points by price proximity
        var clusters: [(price: Double, count: Int, isHigh: Bool)] = []
        let sortedSwings = swings.sorted { $0.price < $1.price }

        for swing in sortedSwings {
            if let last = clusters.last, abs(swing.price - last.price) / max(swing.price, 0.000001) <= clusterTolerance {
                clusters[clusters.count - 1] = (
                    (last.price * Double(last.count) + swing.price) / Double(last.count + 1),
                    last.count + 1,
                    last.isHigh == swing.isHigh ? last.isHigh : last.isHigh
                )
            } else {
                clusters.append((swing.price, 1, swing.isHigh))
            }
        }

        // Filter by minimum touches
        let relevant = clusters.filter { $0.count >= minTouches }
        let price = candles.last?.close ?? 0

        return relevant.map { cluster -> SRL in
            let type: SRType
            if cluster.isHigh {
                type = cluster.count >= 3 && cluster.price > price ? .resistance :
                       cluster.count >= 3 && cluster.price < price ? .support : .both
            } else {
                type = cluster.count >= 3 && cluster.price < price ? .support :
                       cluster.count >= 3 && cluster.price > price ? .resistance : .both
            }
            let strength = min(Double(cluster.count) / 5.0, 1.0)
            let desc = "\(type.rawValue) at \(fmt(cluster.price)) — \(cluster.count) touches"
            return SRL(price: cluster.price, type: type, strength: strength, touches: cluster.count, description: desc)
        }.sorted { $0.strength > $1.strength }
    }

    // MARK: - Volume Pattern Detection

    /// Detect volume-based patterns.
    static func detectVolumePatterns(candles: [Candle], lookback: Int = 60) -> [VolumePattern] {
        guard candles.count >= 20 else { return [] }
        let recent = Array(candles.suffix(min(lookback, candles.count)))
        var patterns: [VolumePattern] = []

        let volumes = recent.map { $0.volume }
        let closes = recent.map { $0.close }
        let avgVol = volumes.reduce(0, +) / Double(volumes.count)
        let recentVol = Double(volumes.suffix(5).reduce(0, +))

        // Volume climax: very high volume compared to average
        let volRatio = recentVol / (avgVol * 5)
        if volRatio > 2.0 {
            let priceUp = (closes.last ?? 0) > (closes.first ?? 0)
            patterns.append(VolumePattern(
                name: "Volume Climax", bullish: !priceUp,
                confidence: min((volRatio - 1) / 3, 0.85),
                index: recent.count - 1,
                description: "Volume climax: \(fmt(volRatio))x average volume — \(priceUp ? "potential selling exhaustion" : "potential buying exhaustion")"
            ))
        }

        // Volume divergence: price making new highs/lows on declining volume
        if recent.count >= 10 {
            let firstVols = Array(volumes.prefix(5))
            let lastVols = Array(volumes.suffix(5))
            let firstAvg = firstVols.reduce(0, +) / Double(firstVols.count)
            let lastAvg = lastVols.reduce(0, +) / Double(lastVols.count)
            let volTrend = lastAvg - firstAvg

            let firstPrice = closes.first ?? 0
            let lastPrice = closes.last ?? 0
            let priceRising = (lastPrice - firstPrice) / max(firstPrice, 0.000001) > 0

            if volTrend < -firstAvg * 0.2 && abs(priceRising) > 0 {
                // Bearish divergence: price up, volume down
                if priceRising {
                    patterns.append(VolumePattern(
                        name: "Bearish Volume Divergence", bullish: false,
                        confidence: min(abs(volTrend) / firstAvg * 0.5, 0.8),
                        index: recent.count - 1,
                        description: "Price rising on declining volume — weak upward momentum"
                    ))
                } else {
                    // Bullish divergence: price down, volume down
                    patterns.append(VolumePattern(
                        name: "Bullish Volume Divergence", bullish: true,
                        confidence: min(abs(volTrend) / firstAvg * 0.5, 0.8),
                        index: recent.count - 1,
                        description: "Price falling on declining volume — selling exhaustion"
                    ))
                }
            }
        }

        // Volume confirmation: strong volume on trending days
        for i in 1..<recent.count {
            let candle = recent[i]
            let prevCandle = recent[i - 1]
            let volIncrease = candle.volume > prevCandle.volume * 1.5
            let bullishMove = candle.close > candle.open && candle.close > prevCandle.close
            let bearishMove = candle.close < candle.open && candle.close < prevCandle.close

            if volIncrease && bullishMove {
                patterns.append(VolumePattern(
                    name: "Bullish Volume Confirmation", bullish: true,
                    confidence: 0.6,
                    index: i,
                    description: "Strong bullish candle with \(fmt(candle.volume / prevCandle.volume))x volume — trend confirmation"
                ))
            } else if volIncrease && bearishMove {
                patterns.append(VolumePattern(
                    name: "Bearish Volume Confirmation", bullish: false,
                    confidence: 0.6,
                    index: i,
                    description: "Strong bearish candle with \(fmt(candle.volume / prevCandle.volume))x volume — trend confirmation"
                ))
            }
        }

        return patterns
    }

    // MARK: - Combined Pattern Report

    /// Generate a comprehensive pattern analysis report.
    static func patternReport(candles: [Candle], symbol: String) -> String {
        let patterns = detectAllPatterns(candles: candles)
        let srLevels = detectSupportResistance(candles: candles)
        let volumePatterns = detectVolumePatterns(candles: candles)

        var report = "## Pattern Recognition — \(DerivSymbols.display(symbol))\n\n"

        // Chart patterns
        if patterns.isEmpty {
            report += "**No significant chart patterns detected.** Markets may be in a smooth drift or range.\n\n"
        } else {
            report += "### Chart Patterns\n\n"
            report += "| Pattern | Type | Direction | Confidence |\n|---|---|---|---|\n"
            for p in patterns.prefix(8) {
                let dirIcon = p.direction.isBullish ? "🟢" : (p.direction.isBearish ? "🔴" : "⚪")
                report += "| \(p.name) | \(p.type.isReversal ? "Reversal" : "Continuation") | \(dirIcon) \(dirLabel(p.direction)) | \(pct(p.confidence)) |\n"
            }
            report += "\n"
        }

        // Support/Resistance
        if !srLevels.isEmpty {
            let price = candles.last?.close ?? 0
            let nearestAbove = srLevels.filter { $0.price > price }.min { $0.price < $1.price }
            let nearestBelow = srLevels.filter { $0.price < price }.max { $0.price > $1.price }

            report += "### Key Levels\n\n"
            report += "| Level | Type | Strength | Touches |\n|---|---|---|---|\n"
            for level in srLevels.prefix(6) {
                report += "| \(fmt(level.price)) | \(level.type.rawValue) | \(pct(level.strength)) | \(level.touches) |\n"
            }
            if let above = nearestAbove {
                report += "\n🔴 **Resistance:** \(fmt(above.price)) (\(above.touches) touches)\n"
            }
            if let below = nearestBelow {
                report += "🟢 **Support:** \(fmt(below.price)) (\(below.touches) touches)\n"
            }
            report += "\n"
        }

        // Volume patterns
        if !volumePatterns.isEmpty {
            report += "### Volume Patterns\n\n"
            for vp in volumePatterns.prefix(4) {
                let icon = vp.bullish ? "🟢" : "🔴"
                report += "- \(icon) **\(vp.name)** (\(pct(vp.confidence))): \(vp.description)\n"
            }
            report += "\n"
        }

        report += "---\n*Pattern recognition is deterministic on-device analysis — not a trading signal.*"

        return report
    }

    // MARK: - Private Helpers

    private static func linearSlope(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let n = values.count
        let xs = (0..<n).map(Double.init)
        let sx = xs.reduce(0, +)
        let sy = values.reduce(0, +)
        let sxx = xs.reduce(0) { $0 + $1 * $1 }
        let sxy = zip(xs, values).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = sxx - sx * sx / Double(n)
        return denom > 0 ? (sxy - sx * sy / Double(n)) / denom : 0
    }

    private static func averageRange(candles: [Candle]) -> Double {
        guard !candles.isEmpty else { return 0 }
        return candles.map { $0.high - $0.low }.reduce(0, +) / Double(candles.count)
    }

    private static func dirLabel(_ d: Direction) -> String {
        switch d {
        case .strongBullish: return "Strong Bullish"
        case .bullish: return "Bullish"
        case .neutral: return "Neutral"
        case .bearish: return "Bearish"
        case .strongBearish: return "Strong Bearish"
        }
    }

    private static func fmt(_ x: Double, _ places: Int = 4) -> String {
        String(format: "%%.\(places)f", x)
    }

    private static func pct(_ x: Double) -> String {
        "\(Int((x * 100).rounded()))%"
    }
}
