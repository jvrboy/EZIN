import Foundation
import Combine

/// Perpetual scalper trading bot. Runs 24/7 across the user's chosen instruments,
/// uses ALL agents/indicators (no single strategy), and — when the bot is switched ON
/// and the account is authorized — places REAL Deriv Multiplier trades that respect the
/// user's BotConfig (stake, instruments, max open positions, stops).
///
/// Signal scanning runs continuously to feed the Signals tab; trade execution only
/// happens while the bot is running.
///
/// Isolated to the main actor so that `running`, `lastVotes` and `placing` are never
/// mutated concurrently from the background scan `Task` (they previously raced). All
/// network calls are `await`ed and suspend without blocking the UI.
@MainActor
final class BotRuntime: ObservableObject {
    private let deriv: DerivClient
    private let engine: SignalEngine
    private let configStore = BotConfigStore.shared

    @Published var running = false
    @Published var sessionLabel = TradingSession.label()
    private var scanTask: Task<Void, Never>?

    var onSignals: (([TradingSignal]) -> Void)?
    var lastVotes: [AgentVote] = []
    private var placing = Set<String>()          // symbols with an in-flight order

    // Multi-timeframe scanning state.
    private lazy var mtf = MultiTimeframeEngine(deriv: deriv, engine: engine)
    private var rotationIndex = 0
    private let scanBatchSize = 4                 // symbols analysed per tick (bounded latency)
    private var liveSignals: [String: TradingSignal] = [:]

    init(deriv: DerivClient, engine: SignalEngine) {
        self.deriv = deriv
        self.engine = engine
    }

    var config: BotConfig { configStore.config }

    /// Always-on signal scanning (does NOT place trades).
    /// Cadence is session-aware: synthetics are hunted 24/7; FX/crypto scan faster in
    /// the quiet 23:00–05:00 SAST window. Signals are multi-timeframe confirmed.
    func startScanning() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.scan()
                let secs = TradingSession.globalScanSeconds(for: self.scanSymbolUniverse())
                self.sessionLabel = TradingSession.label()
                try? await Task.sleep(nanoseconds: max(3, secs) * 1_000_000_000)
            }
        }
    }

    func stopScanning() { scanTask?.cancel(); scanTask = nil }

    /// The full set of symbols to scan. When idle, synthetics are always included so
    /// they produce signals around the clock, alongside the user's watchlist.
    func scanSymbolUniverse() -> [String] {
        if running { return config.instruments }
        var set = SettingsStore.shared.watchlist
        let alwaysOn = DerivSymbols.volatility + DerivSymbols.boom + DerivSymbols.crash + DerivSymbols.jump
        for s in alwaysOn where !set.contains(s) { set.append(s) }
        return set
    }

    private func nextBatch(from universe: [String]) -> [String] {
        guard !universe.isEmpty else { return [] }
        if rotationIndex >= universe.count { rotationIndex = 0 }
        let end = min(rotationIndex + scanBatchSize, universe.count)
        let slice = Array(universe[rotationIndex..<end])
        rotationIndex = end
        return slice
    }

    /// Switch the trading bot ON — begins executing trades on scans.
    func startBot() {
        running = true
        for s in config.instruments { deriv.subscribeTicks(s) }
    }

    func stopBot() { running = false }

    // MARK: - Core scan

    private func scan() async {
        let universe = scanSymbolUniverse()
        let batch = nextBatch(from: universe)
        guard !batch.isEmpty else { onSignals?(sortedLiveSignals()); return }

        var newSignals: [TradingSignal] = []
        for symbol in batch {
            let asset = DerivSymbols.assetClass(symbol)
            let pol = TradingSession.policy(for: asset)

            // Deep multi-timeframe confirmation (not a single-1m read).
            guard let report = await mtf.analyze(symbol: symbol, requested: pol.baseTimeframe, candleCount: 160) else { continue }
            lastVotes = report.requestedFocus.topVotes

            guard let sig = report.toSignal(strategy: pol.aggressive ? "MTF · Overnight Hunt" : "MTF Confluence"),
                  sig.confidence >= pol.minConfidence else { continue }
            newSignals.append(sig)

            // Execute only when bot is ON, authorized, and the signal clears the user's gate.
            if running, deriv.authorized, sig.confidence >= config.minConfidence * 100 {
                var md = MarketData(symbol: symbol, assetClass: asset, timeframe: pol.baseTimeframe, candles: [])
                md.currentPrice = report.verdict.entry
                await maybeTrade(signal: sig, md: md)
            }
        }

        mergeSignals(newSignals)
    }

    /// Merge freshly-scanned signals into the rolling live set (one per symbol),
    /// dropping expired entries, then publish the sorted list.
    private func mergeSignals(_ new: [TradingSignal]) {
        for s in new { liveSignals[s.symbol] = s }
        let now = Date()
        liveSignals = liveSignals.filter { $0.value.expiresAt > now }
        onSignals?(sortedLiveSignals())
    }

    private func sortedLiveSignals() -> [TradingSignal] {
        liveSignals.values.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Trade execution

    private func maybeTrade(signal: TradingSignal, md: MarketData) async {
        // Respect max open positions.
        guard deriv.openPositionCount < config.maxOpenPositions else { return }
        // One position per symbol.
        guard !deriv.positions.values.contains(where: { $0.symbol == md.symbol && !$0.isSold }) else { return }
        guard !placing.contains(md.symbol) else { return }
        placing.insert(md.symbol)
        defer { placing.remove(md.symbol) }

        let (sl, tp) = computeStops(signal: signal, md: md)
        do {
            let prop = try await deriv.proposal(
                symbol: md.symbol, up: signal.isBuy,
                stake: config.fixedLotSize, multiplier: config.multiplier,
                currency: deriv.currency, stopLoss: sl, takeProfit: tp)
            _ = try await deriv.buy(proposalId: prop.id, price: prop.price)
        } catch {
            // Already on the main actor — surface the failure directly.
            deriv.lastError = error.localizedDescription
        }
    }

    /// Convert the configured stop mode into Deriv Multiplier limit_order amounts (account currency).
    /// For multipliers, P&L ≈ stake * multiplier * (Δprice / entryPrice).
    private func computeStops(signal: TradingSignal, md: MarketData) -> (stopLoss: Double?, takeProfit: Double?) {
        let stake = config.fixedLotSize
        let mult = Double(config.multiplier)
        let entry = signal.entry > 0 ? signal.entry : (md.currentPrice > 0 ? md.currentPrice : 1)

        func amount(forPriceMove move: Double) -> Double {
            guard entry > 0 else { return 0 }
            return abs(stake * mult * (move / entry))
        }

        switch config.stopMode {
        case .profit:
            return (config.stopLossValue > 0 ? config.stopLossValue : nil,
                    config.takeProfitValue > 0 ? config.takeProfitValue : nil)
        case .points, .pips:
            let unit = DerivSymbols.pointSize(md.symbol)
            let sl = amount(forPriceMove: config.stopLossValue * unit)
            let tp = amount(forPriceMove: config.takeProfitValue * unit)
            return (sl > 0 ? sl : nil, tp > 0 ? tp : nil)
        case .botChoice:
            // Use the engine's ATR-derived SL/TP distances.
            let slMove = abs(signal.entry - signal.stopLoss)
            let tpMove = abs(signal.takeProfit - signal.entry)
            let sl = amount(forPriceMove: slMove)
            let tp = amount(forPriceMove: tpMove)
            return (sl > 0 ? sl : nil, tp > 0 ? tp : nil)
        }
    }
}
