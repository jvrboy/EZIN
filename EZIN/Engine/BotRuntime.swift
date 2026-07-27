import Foundation
import Combine

/// Paper-first multi-timeframe signal bot. It scans the user's chosen instruments and
/// uses the full council/indicator stack. Paper positions are the default; live Deriv
/// orders require an authorized account, live mode, explicit arming, and the configured
/// risk limits. iOS background execution is best-effort rather than guaranteed 24/7.
///
/// Signal scanning feeds the Signals tab; execution only happens while the bot is running.
///
/// Isolated to the main actor so that `running`, `lastVotes` and `placing` are never
/// mutated concurrently from the background scan `Task` (they previously raced). All
/// network calls are `await`ed and suspend without blocking the UI.
struct PaperPosition: Identifiable {
    let id = UUID()
    let symbol: String
    let isBuy: Bool
    let entryPrice: Double
    let stopLoss: Double
    let takeProfit: Double
    let openedAt: Date
    let pnlFactor: Double
    var lastPrice: Double
    var realizedPnL: Double?
    var closedAt: Date?

    var isOpen: Bool { realizedPnL == nil }
    var floatingPnL: Double {
        (isBuy ? lastPrice - entryPrice : entryPrice - lastPrice) * pnlFactor
    }
}

@MainActor
final class BotRuntime: ObservableObject {
    private let deriv: DerivClient
    private let engine: SignalEngine
    private let configStore = BotConfigStore.shared

    @Published var running = false
    @Published var sessionLabel = TradingSession.label()
    @Published private(set) var paperPositions: [PaperPosition] = []
    @Published private(set) var dailyTradeCount = 0
    @Published private(set) var dailyPnL = 0.0
    @Published private(set) var liveTradingArmed = false
    private var sessionDay = Calendar.current.startOfDay(for: Date())
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

    var paperOpenPnL: Double {
        paperPositions.filter(\.isOpen).reduce(0) { $0 + $1.floatingPnL }
    }

    func armLiveTrading() {
        guard config.executionMode == .live, deriv.authorized else { return }
        liveTradingArmed = true
    }

    func disarmLiveTrading() {
        liveTradingArmed = false
    }

    func resetRiskSession() {
        sessionDay = Calendar.current.startOfDay(for: Date())
        dailyTradeCount = 0
        dailyPnL = 0
    }

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
        if config.executionMode == .live {
            liveTradingArmed = !config.requireOrderPreview && deriv.authorized
        }
        for s in config.instruments { deriv.subscribeTicks(s) }
    }

    func stopBot() {
        running = false
        liveTradingArmed = false
    }

    // MARK: - Core scan

    private func scan() async {
        if config.executionMode != .live || !deriv.authorized { liveTradingArmed = false }
        rotateRiskSessionIfNeeded()
        updatePaperPositions()
        let universe = scanSymbolUniverse()
        let batch = nextBatch(from: universe)
        guard !batch.isEmpty else { onSignals?(sortedLiveSignals()); return }

        var newSignals: [TradingSignal] = []
        for symbol in batch { deriv.subscribeTicks(symbol) }
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
            if running,
               (config.executionMode == .paper || deriv.authorized),
               sig.confidence >= config.minConfidence * 100 {
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
        guard config.dailyTradeLimit <= 0 || dailyTradeCount < config.dailyTradeLimit else { return }
        let floatingRisk = config.executionMode == .paper ? paperOpenPnL : deriv.totalOpenProfit
        guard config.dailyLossLimit <= 0 || dailyPnL + floatingRisk > -config.dailyLossLimit else { return }

        let (sl, tp) = computeStops(signal: signal, md: md)
        guard sl != nil, tp != nil else { return }

        if config.executionMode == .paper {
            guard paperPositions.filter(\.isOpen).count < config.maxOpenPositions else { return }
            guard !paperPositions.contains(where: { $0.symbol == md.symbol && $0.isOpen }) else { return }
            let factor = config.fixedLotSize * Double(config.multiplier) / max(signal.entry, 0.000001)
            let position = PaperPosition(
                symbol: md.symbol, isBuy: signal.isBuy, entryPrice: signal.entry,
                stopLoss: signal.stopLoss, takeProfit: signal.takeProfit,
                openedAt: Date(), pnlFactor: factor, lastPrice: signal.entry,
                realizedPnL: nil, closedAt: nil
            )
            paperPositions.append(position)
            dailyTradeCount += 1
            return
        }

        guard liveTradingArmed else { return }
        if config.stalePriceSeconds > 0 {
            guard let updated = deriv.lastPriceUpdateAt[md.symbol],
                  Date().timeIntervalSince(updated) <= config.stalePriceSeconds else { return }
        }
        // Respect max open positions.
        guard deriv.openPositionCount < config.maxOpenPositions else { return }
        // One position per symbol.
        guard !deriv.positions.values.contains(where: { $0.symbol == md.symbol && !$0.isSold }) else { return }
        guard !placing.contains(md.symbol) else { return }
        placing.insert(md.symbol)
        defer { placing.remove(md.symbol) }

        do {
            let prop = try await deriv.proposal(
                symbol: md.symbol, up: signal.isBuy,
                stake: config.fixedLotSize, multiplier: config.multiplier,
                currency: deriv.currency, stopLoss: sl, takeProfit: tp)
            _ = try await deriv.buy(proposalId: prop.id, price: prop.price)
            dailyTradeCount += 1
        } catch {
            // Already on the main actor — surface the failure directly.
            deriv.lastError = error.localizedDescription
        }
    }

    private func rotateRiskSessionIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != sessionDay {
            sessionDay = today
            dailyTradeCount = 0
            dailyPnL = 0
        }
    }

    private func updatePaperPositions() {
        guard !paperPositions.isEmpty else { return }
        for i in paperPositions.indices where paperPositions[i].isOpen {
            guard let price = deriv.prices[paperPositions[i].symbol] else { continue }
            var position = paperPositions[i]
            position.lastPrice = price
            let hitTP = position.isBuy ? price >= position.takeProfit : price <= position.takeProfit
            let hitSL = position.isBuy ? price <= position.stopLoss : price >= position.stopLoss
            let expired = Date().timeIntervalSince(position.openedAt) >= 30 * 60
            if hitTP || hitSL || expired {
                position.realizedPnL = position.floatingPnL
                position.closedAt = Date()
                dailyPnL += position.floatingPnL
            }
            paperPositions[i] = position
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
