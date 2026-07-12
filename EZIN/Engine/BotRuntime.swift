import Foundation

/// Always-on backend runtime. Bots & agents run hidden here: it polls Deriv,
/// runs the signal engine per symbol, and pushes signals/outcomes to the UI.
final class BotRuntime {
    private let deriv: DerivClient
    private let engine: SignalEngine
    private var loopTask: Task<Void, Never>?
    private(set) var running = false

    var onSignals: (([TradingSignal]) -> Void)?
    var onOutcome: ((SignalOutcome) -> Void)?
    var lastVotes: [AgentVote] = []

    var refreshSeconds: UInt64 = 20

    init(deriv: DerivClient, engine: SignalEngine) {
        self.deriv = deriv
        self.engine = engine
    }

    func start(symbols: [String]) async {
        guard !running else { return }
        running = true
        loopTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled && self.running {
                await self.tick(symbols: symbols)
                try? await Task.sleep(nanoseconds: self.refreshSeconds * 1_000_000_000)
            }
        }
    }

    func stop() async {
        running = false
        loopTask?.cancel()
        loopTask = nil
    }

    private func tick(symbols: [String]) async {
        var signals: [TradingSignal] = []
        for symbol in symbols {
            let tf = Timeframe.m5
            let candles = await fetchCandles(symbol: symbol, timeframe: tf)
            guard candles.count > 30 else { continue }
            var md = MarketData(symbol: symbol, assetClass: DerivSymbols.assetClass(symbol),
                                timeframe: tf, candles: candles)
            md.currentPrice = candles.last?.close ?? 0
            if let sig = engine.generate(for: md) {
                signals.append(sig)
                lastVotes = engine.agents.filter { $0.isActive }.map { $0.analyze(md, engine.analyzer.analyze(md)) }
            }
        }
        signals.sort { $0.confidence > $1.confidence }
        onSignals?(signals)
    }

    /// Try live Deriv data; fall back to a locally-simulated series so the app
    /// remains functional offline / before credentials are set.
    private func fetchCandles(symbol: String, timeframe: Timeframe) async -> [Candle] {
        if let live = try? await deriv.candles(symbol: symbol, timeframe: timeframe, count: 200), !live.isEmpty {
            return live
        }
        return SyntheticFeed.candles(symbol: symbol, count: 200)
    }
}

/// Deterministic-ish random-walk feed used as an offline fallback.
enum SyntheticFeed {
    static func candles(symbol: String, count: Int) -> [Candle] {
        var seed = UInt64(abs(symbol.hashValue) % 100_000 + 1)
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let base: Double = symbol.contains("BTC") ? 61000 : symbol.contains("XAU") ? 2400 :
                            symbol.hasPrefix("R_") ? 3800 : 1.08
        var price = base
        var out = [Candle]()
        let now = Date()
        for i in 0..<count {
            let drift = (rnd() - 0.5) * base * 0.004
            let open = price
            let close = max(price + drift, base * 0.2)
            let high = max(open, close) + rnd() * base * 0.001
            let low = min(open, close) - rnd() * base * 0.001
            price = close
            out.append(Candle(timestamp: now.addingTimeInterval(Double(i - count) * 300),
                              open: open, high: high, low: low, close: close, volume: rnd() * 1000 + 200))
        }
        return out
    }
}
