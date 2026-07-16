import Foundation

/// Price-structure backend: support/resistance, supply/demand zones, RSI/MACD divergence,
/// and a deliberately conservative multi-specialist consensus. All outputs are advisory.
enum ConfluenceAnalysisEngine {
    enum ZoneKind: String { case support, resistance, demand, supply }
    struct Zone: Identifiable {
        let id = UUID()
        let kind: ZoneKind
        let lower: Double
        let upper: Double
        let touches: Int
        let score: Double
    }
    struct StructureReport {
        let zones: [Zone]
        let divergences: [DivergenceEngine.Divergence]
        let direction: Direction
        let confidence: Int
        let rationale: [String]
    }

    static func analyze(_ md: MarketData) -> StructureReport {
        guard md.candles.count >= 30 else {
            return StructureReport(zones: [], divergences: [], direction: .neutral, confidence: 0, rationale: ["Need at least 30 candles for structure analysis."])
        }
        let prices = md.closes
        let pivots = DivergenceEngine.findPivots(prices, leftBars: 3, rightBars: 3)
        let atr = average(zip(md.highs, md.lows).suffix(14).map { $0.0 - $0.1 })
        let width = max(atr * 0.35, abs(prices.last ?? 0) * 0.0001)
        let supports = cluster(pivots.lows.map(\.value), kind: .support, width: width)
        let resistances = cluster(pivots.highs.map(\.value), kind: .resistance, width: width)
        let supplyDemand = impulseZones(md, width: width)
        let rsi = Indicators.rsi(prices, 14)
        let macd = Indicators.macd(prices).histogram
        let divergences = (DivergenceEngine.detect(price: prices, indicator: rsi) + DivergenceEngine.detect(price: prices, indicator: macd)).sorted { $0.at > $1.at }
        let latest = prices.last ?? 0
        let recent = Array(divergences.prefix(4))
        let divergenceScore = recent.reduce(0.0) { $0 + ($1.type.isBullish ? 1 : -1) }
        let nearbySupport = supports.contains { latest >= $0.lower && latest <= $0.upper * 1.002 }
        let nearbyResistance = resistances.contains { latest >= $0.lower * 0.998 && latest <= $0.upper }
        let systematic = BackendQuantEngine.systematic(md)
        let score = directionValue(systematic.direction) * 0.5 + divergenceScore * 0.25 + (nearbySupport ? 0.25 : 0) - (nearbyResistance ? 0.25 : 0)
        let direction: Direction = score > 0.6 ? .bullish : (score < -0.6 ? .bearish : .neutral)
        var rationale = ["Systematic backend: \(label(systematic.direction)) (\(systematic.confidence)/100)."]
        if nearbySupport { rationale.append("Price is interacting with clustered support.") }
        if nearbyResistance { rationale.append("Price is interacting with clustered resistance.") }
        if let first = recent.first { rationale.append("Latest oscillator divergence: \(first.type.rawValue).") }
        if rationale.count == 1 { rationale.append("No high-confluence structure interaction detected.") }
        return StructureReport(zones: supports + resistances + supplyDemand, divergences: recent, direction: direction, confidence: min(95, Int(abs(score) * 50 + Double(recent.count) * 8)), rationale: rationale)
    }

    static func formatted(_ report: StructureReport, symbol: String) -> String {
        let zones = report.zones.sorted { $0.score > $1.score }.prefix(8).map { zone in
            "- \(zone.kind.rawValue.capitalized): \(format(zone.lower)) – \(format(zone.upper)) (\(zone.touches) confirmations)"
        }.joined(separator: "\n")
        let divs = report.divergences.map { "- \($0.type.rawValue) at \(format($0.price))" }.joined(separator: "\n")
        return """
        ## Structure Confluence — \(symbol)
        **Directional bias:** \(label(report.direction)) · **Confluence:** \(report.confidence)/100

        **Support / resistance / supply / demand**
        \(zones.isEmpty ? "- No validated zones yet." : zones)

        **Divergences**
        \(divs.isEmpty ? "- No recent RSI/MACD divergence." : divs)

        **Decision notes**
        \(report.rationale.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func cluster(_ values: [Double], kind: ZoneKind, width: Double) -> [Zone] {
        guard !values.isEmpty else { return [] }
        var groups: [[Double]] = []
        for value in values.sorted() {
            if let index = groups.indices.min(by: { abs(average(groups[$0]) - value) < abs(average(groups[$1]) - value) }), abs(average(groups[index]) - value) <= width {
                groups[index].append(value)
            } else { groups.append([value]) }
        }
        return groups.filter { $0.count >= 2 }.map { group in
            let center = average(group)
            return Zone(kind: kind, lower: center - width, upper: center + width, touches: group.count, score: Double(group.count))
        }
    }

    private static func impulseZones(_ md: MarketData, width: Double) -> [Zone] {
        let ranges = zip(md.highs, md.lows).map { $0.0 - $0.1 }
        let baseline = average(Array(ranges.suffix(30)))
        guard baseline > 0 else { return [] }
        return Array(md.candles.enumerated().compactMap { index, candle in
            guard index > 0, ranges[index] > baseline * 1.8 else { return nil }
            if candle.isBullish { return Zone(kind: .demand, lower: candle.low - width, upper: candle.open + width, touches: 1, score: ranges[index] / baseline) }
            if candle.isBearish { return Zone(kind: .supply, lower: candle.open - width, upper: candle.high + width, touches: 1, score: ranges[index] / baseline) }
            return nil
        }.suffix(6))
    }

    private static func average(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    private static func directionValue(_ direction: Direction) -> Double { Double(direction.rawValue) / 2 }
    private static func format(_ value: Double) -> String { String(format: "%.5f", value) }
    private static func label(_ direction: Direction) -> String { switch direction { case .strongBullish: return "Strong bullish"; case .bullish: return "Bullish"; case .neutral: return "Neutral"; case .bearish: return "Bearish"; case .strongBearish: return "Strong bearish" } }
}
