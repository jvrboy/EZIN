import Foundation
import Combine

/// Perpetual scalper trading bot. Runs 24/7 across the user's chosen instruments,
/// uses ALL agents/indicators (no single strategy), and — when the bot is switched ON
/// and the account is authorized — places REAL Deriv Multiplier trades that respect the
/// user's BotConfig (stake, instruments, max open positions, stops).
///
/// Signal scanning runs continuously to feed the Signals tab; trade execution only
/// happens while the bot is running.
final class BotRuntime: ObservableObject {
    private let deriv: DerivClient
    private let engine: SignalEngine
    private let configStore = BotConfigStore.shared

    @Published var running = false
    private var scanTask: Task<Void, Never>?

    var onSignals: (([TradingSignal]) -> Void)?
    var lastVotes: [AgentVote] = []
    var scanSeconds: UInt64 = 10          // fast cadence for a scalper
    private var placing = Set<String>()   // symbols with an in-flight order

    init(deriv: DerivClient, engine: SignalEngine) {
        self.deriv = deriv
        self.engine = engine
    }

    var config: BotConfig { configStore.config }

    /// Always-on signal scanning (does NOT place trades).
    func startScanning() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.scan()
                try? await Task.sleep(nanoseconds: self.scanSeconds * 1_000_000_000)
            }
        }
    }

    func stopScanning() { scanTask?.cancel(); scanTask = nil }

    /// Switch the trading bot ON — begins executing trades on scans.
    func startBot() {
        running = true
        for s in config.instruments { deriv.subscribeTicks(s) }
    }

    func stopBot() { running = false }

    // MARK: - Core scan

    private func scan() async {
        let symbols = running ? config.instruments : SettingsStore.shared.watchlist
        var signals: [TradingSignal] = []

        for symbol in symbols {
            guard let candles = try? await deriv.candles(symbol: symbol, timeframe: .m1, count: 150),
                  candles.count > 40 else { continue }
            var md = MarketData(symbol: symbol, assetClass: DerivSymbols.assetClass(symbol),
                                timeframe: .m1, candles: candles)
            md.currentPrice = deriv.prices[symbol] ?? candles.last?.close ?? 0

            guard let sig = engine.generate(for: md, strategyName: "Perpetual Scalper") else { continue }
            signals.append(sig)
            lastVotes = engine.agents.filter { $0.isActive }.map { $0.analyze(md, engine.analyzer.analyze(md)) }

            // Execute only when bot is ON, authorized, and the signal is high-probability.
            if running, deriv.authorized, sig.confidence >= config.minConfidence * 100 {
                await maybeTrade(signal: sig, md: md)
            }
        }

        signals.sort { $0.confidence > $1.confidence }
        onSignals?(signals)
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
            DispatchQueue.main.async { self.deriv.lastError = error.localizedDescription }
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
