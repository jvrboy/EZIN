import Foundation
import Combine

/// Tracks signal performance over time: monitors whether signals hit TP, SL, or expire.
/// Provides accuracy metrics and self-improvement data for the neural learning system.
@MainActor
final class SignalPerformanceStore: ObservableObject {
    static let shared = SignalPerformanceStore()

    @Published var trackedSignals: [TrackedSignal] = []
    @Published var dailyMetrics: DailyMetrics = DailyMetrics()

    private let file = "signal_performance.json"
    private let metricsFile = "signal_daily_metrics.json"
    private let maxItems = 500
    private var updateTimer: Timer?

    private init() {
        load()
        startMonitoring()
    }

    // MARK: - Tracking

    /// Begin tracking a newly generated signal.
    func track(_ signal: TradingSignal, currentPrice: Double) {
        let tracked = TrackedSignal(
            signal: signal,
            entryPrice: currentPrice,
            status: .active,
            bestPrice: currentPrice,
            worstPrice: currentPrice,
            monitoringStartedAt: Date()
        )
        trackedSignals.insert(tracked, at: 0)
        enforceLimit()
        save()
    }

    /// Update tracked signals with latest price data.
    func updatePrices(_ prices: [String: Double]) {
        var changed = false
        for i in trackedSignals.indices where trackedSignals[i].status == .active {
            let symbol = trackedSignals[i].signal.symbol
            guard let price = prices[symbol] else { continue }

            var t = trackedSignals[i]
            t.lastPrice = price
            t.bestPrice = t.signal.isBuy ? max(t.bestPrice, price) : min(t.bestPrice, price)
            t.worstPrice = t.signal.isBuy ? min(t.worstPrice, price) : max(t.worstPrice, price)

            // Floating P&L
            if t.signal.isBuy {
                t.floatingPnL = price - t.entryPrice
                // Check TP hit
                if price >= t.signal.takeProfit {
                    t.status = .hitTakeProfit
                    t.exitPrice = price
                    t.exitTime = Date()
                    dailyMetrics.recordWin(pnl: t.floatingPnL, symbol: symbol, timeframe: t.signal.timeframe)
                }
                // Check SL hit
                else if price <= t.signal.stopLoss {
                    t.status = .hitStopLoss
                    t.exitPrice = price
                    t.exitTime = Date()
                    dailyMetrics.recordLoss(pnl: t.floatingPnL, symbol: symbol, timeframe: t.signal.timeframe)
                }
            } else {
                t.floatingPnL = t.entryPrice - price
                // Check TP hit (for sell, TP is below entry)
                if price <= t.signal.takeProfit {
                    t.status = .hitTakeProfit
                    t.exitPrice = price
                    t.exitTime = Date()
                    dailyMetrics.recordWin(pnl: t.floatingPnL, symbol: symbol, timeframe: t.signal.timeframe)
                }
                // Check SL hit (for sell, SL is above entry)
                else if price >= t.signal.stopLoss {
                    t.status = .hitStopLoss
                    t.exitPrice = price
                    t.exitTime = Date()
                    dailyMetrics.recordLoss(pnl: t.floatingPnL, symbol: symbol, timeframe: t.signal.timeframe)
                }
            }

            // Check expiry
            if t.status == .active && Date() > t.signal.expiresAt {
                t.status = .expired
                t.exitPrice = price
                t.exitTime = Date()
                if t.floatingPnL >= 0 {
                    dailyMetrics.recordWin(pnl: t.floatingPnL, symbol: symbol, timeframe: t.signal.timeframe)
                } else {
                    dailyMetrics.recordLoss(pnl: t.floatingPnL, symbol: symbol, timeframe: t.signal.timeframe)
                }
            }

            trackedSignals[i] = t
            changed = true
        }
        if changed {
            save()
        }
    }

    // MARK: - Queries

    func activeSignals() -> [TrackedSignal] {
        trackedSignals.filter { $0.status == .active }
    }

    func resolvedSignals() -> [TrackedSignal] {
        trackedSignals.filter { $0.status != .active }
    }

    func signalsForSymbol(_ symbol: String) -> [TrackedSignal] {
        trackedSignals.filter { $0.signal.symbol == symbol }
    }

    func signalsForTimeframe(_ tf: Timeframe) -> [TrackedSignal] {
        trackedSignals.filter { $0.signal.timeframe == tf }
    }

    /// Overall win rate across all resolved signals.
    var overallWinRate: Double {
        let resolved = resolvedSignals()
        guard !resolved.isEmpty else { return 0 }
        let wins = resolved.filter { $0.isWin }.count
        return Double(wins) / Double(resolved.count)
    }

    /// Win rate for a specific symbol.
    func winRate(for symbol: String) -> Double {
        let resolved = signalsForSymbol(symbol).filter { $0.status != .active }
        guard !resolved.isEmpty else { return 0 }
        return Double(resolved.filter { $0.isWin }.count) / Double(resolved.count)
    }

    /// Average reward-to-risk ratio of resolved signals.
    var averageRR: Double {
        let resolved = resolvedSignals()
        guard !resolved.isEmpty else { return 0 }
        return resolved.map { $0.signal.riskReward }.reduce(0, +) / Double(resolved.count)
    }

    /// Best and worst performing symbols.
    var symbolRankings: [(symbol: String, winRate: Double, count: Int)] {
        let symbols = Set(trackedSignals.map { $0.signal.symbol })
        return symbols.map { sym in
            (sym, winRate(for: sym), signalsForSymbol(sym).count)
        }.sorted { $0.winRate > $1.winRate }
    }

    /// Get recommendations based on performance data.
    func recommendations() -> [String] {
        var recs: [String] = []
        let resolved = resolvedSignals()
        guard resolved.count >= 5 else {
            return ["Need at least 5 resolved signals for recommendations. Currently: \(resolved.count)."]
        }

        // Win rate analysis
        let wr = overallWinRate
        if wr < 0.4 {
            recs.append("Overall win rate (\(Int(wr * 100))%) is low. Consider requiring higher confidence thresholds or more confluence.")
        } else if wr > 0.65 {
            recs.append("Strong win rate (\(Int(wr * 100))%). Current strategy is effective.")
        }

        // Symbol-specific advice
        let rankings = symbolRankings
        if let best = rankings.first, best.count >= 3 {
            recs.append("Best performer: \(DerivSymbols.display(best.symbol)) (\(Int(best.winRate * 100))% WR over \(best.count) signals).")
        }
        if let worst = rankings.last, worst.count >= 3, worst.winRate < 0.35 {
            recs.append("Worst performer: \(DerivSymbols.display(worst.symbol)) (\(Int(worst.winRate * 100))% WR). Consider avoiding.")
        }

        // Timeframe analysis
        let tfStats = Timeframe.allCases.map { tf -> (Timeframe, Double, Int) in
            let s = signalsForTimeframe(tf).filter { $0.status != .active }
            let wr = s.isEmpty ? 0 : Double(s.filter { $0.isWin }.count) / Double(s.count)
            return (tf, wr, s.count)
        }.filter { $0.2 >= 3 }.sorted { $0.1 > $1.1 }

        if let bestTF = tfStats.first {
            recs.append("Best timeframe: \(bestTF.0.rawValue) (\(Int(bestTF.1 * 100))% WR over \(bestTF.2) signals).")
        }

        return recs
    }

    // MARK: - Persistence

    private func enforceLimit() {
        if trackedSignals.count > maxItems {
            // Keep all active signals, trim oldest resolved ones.
            let active = trackedSignals.filter { $0.status == .active }
            let resolved = trackedSignals.filter { $0.status != .active }
                .sorted { ($0.exitTime ?? Date.distantPast) > ($1.exitTime ?? Date.distantPast) }
            let keepResolved = max(0, maxItems - active.count)
            trackedSignals = active + resolved.prefix(keepResolved)
        }
    }

    private func startMonitoring() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            // Price updates are pushed from AppState via updatePrices(_:)
        }
    }

    private func save() {
        FileStore.shared.write(trackedSignals, to: file, in: FileStore.shared.dataDir)
        if let data = try? JSONEncoder().encode(dailyMetrics) {
            FileStore.shared.writeRaw(data, to: metricsFile, in: FileStore.shared.dataDir)
        }
    }

    private func load() {
        trackedSignals = FileStore.shared.read([TrackedSignal].self, from: file, in: FileStore.shared.dataDir) ?? []
        if let data = FileStore.shared.readRaw(from: metricsFile, in: FileStore.shared.dataDir),
           let m = try? JSONDecoder().decode(DailyMetrics.self, from: data) {
            dailyMetrics = m
        }
    }

    func clear() {
        trackedSignals.removeAll()
        dailyMetrics = DailyMetrics()
        save()
    }
}

// MARK: - TrackedSignal Model

struct TrackedSignal: Codable, Identifiable {
    let id: UUID
    let signal: TradingSignal
    let entryPrice: Double
    var lastPrice: Double?
    var exitPrice: Double?
    var exitTime: Date?
    var floatingPnL: Double = 0
    var bestPrice: Double
    var worstPrice: Double
    var status: SignalResolutionStatus
    let monitoringStartedAt: Date

    var isWin: Bool { floatingPnL > 0 }
    var isResolved: Bool { status != .active }
    var maxDrawdown: Double { abs(entryPrice - worstPrice) }
    var maxRunup: Double { abs(bestPrice - entryPrice) }
    var holdingTime: TimeInterval? {
        guard let exit = exitTime else { return nil }
        return exit.timeIntervalSince(monitoringStartedAt)
    }

    init(signal: TradingSignal, entryPrice: Double, status: SignalResolutionStatus, bestPrice: Double, worstPrice: Double, monitoringStartedAt: Date) {
        self.id = signal.id
        self.signal = signal
        self.entryPrice = entryPrice
        self.lastPrice = entryPrice
        self.status = status
        self.bestPrice = bestPrice
        self.worstPrice = worstPrice
        self.monitoringStartedAt = monitoringStartedAt
    }
}

enum SignalResolutionStatus: String, Codable {
    case active, hitTakeProfit, hitStopLoss, expired
}

// MARK: - DailyMetrics

struct DailyMetrics: Codable {
    struct SymbolTFRecord: Codable {
        var wins: Int = 0
        var losses: Int = 0
        var totalPnL: Double = 0
    }

    var date: Date = Date()
    var totalSignals: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    var totalPnL: Double = 0
    var bySymbol: [String: SymbolTFRecord] = [:]
    var byTimeframe: [String: SymbolTFRecord] = [:]

    var winRate: Double { totalSignals > 0 ? Double(wins) / Double(totalSignals) : 0 }
    var profitFactor: Double { losses > 0 ? Double(wins) / Double(losses) : 0 }

    mutating func recordWin(pnl: Double, symbol: String, timeframe: Timeframe) {
        totalSignals += 1; wins += 1; totalPnL += pnl
        bySymbol[symbol, default: SymbolTFRecord()].wins += 1
        bySymbol[symbol, default: SymbolTFRecord()].totalPnL += pnl
        byTimeframe[timeframe.rawValue, default: SymbolTFRecord()].wins += 1
        byTimeframe[timeframe.rawValue, default: SymbolTFRecord()].totalPnL += pnl
    }

    mutating func recordLoss(pnl: Double, symbol: String, timeframe: Timeframe) {
        totalSignals += 1; losses += 1; totalPnL += pnl
        bySymbol[symbol, default: SymbolTFRecord()].losses += 1
        bySymbol[symbol, default: SymbolTFRecord()].totalPnL += pnl
        byTimeframe[timeframe.rawValue, default: SymbolTFRecord()].losses += 1
        byTimeframe[timeframe.rawValue, default: SymbolTFRecord()].totalPnL += pnl
    }
}
