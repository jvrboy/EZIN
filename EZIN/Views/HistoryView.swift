import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var signalLog = SignalHistoryStore.shared
    @ObservedObject private var performance = SignalPerformanceStore.shared
    @State private var mode = 0   // 0 = closed trades, 1 = generated signals

    private var wins: Int { app.history.filter { $0.profit > 0 }.count }
    private var winRate: Int { app.history.isEmpty ? 0 : Int(Double(wins) / Double(app.history.count) * 100) }
    private var netPnL: Double { app.history.reduce(0) { $0 + $1.profit } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("", selection: $mode) {
                    Text("Trades").tag(0)
                    Text("Signals").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 { tradesSection } else { signalsPerformanceSection }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .refreshable { await app.refreshHistory() }
    }

    // MARK: Closed trades (requires Deriv token)
    private var tradesSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                StatCard(value: "\(winRate)%", label: "Win rate", color: .white)
                StatCard(value: "\(wins)", label: "Wins", color: Glass.buy)
                StatCard(value: "\(app.history.count - wins)", label: "Losses", color: Glass.sell)
            }

            if app.history.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath",
                           title: app.deriv.authorized ? "No closed trades yet" : "Connect your account",
                           subtitle: app.deriv.authorized
                            ? "Closed trades from your Deriv account will appear here."
                            : "Add your Deriv API token in Settings to sync your real trade history. Generated signals are under the Signals tab and need no token.")
            } else {
                HStack {
                    Text("Net P&L").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(String(format: "%@%.2f %@", netPnL >= 0 ? "+" : "", netPnL, app.deriv.currency))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(netPnL >= 0 ? Glass.buy : Glass.sell)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).glassCard()

                VStack(spacing: 0) {
                    ForEach(Array(app.history.enumerated()), id: \.element.id) { idx, h in
                        HStack {
                            Circle().fill(h.profit > 0 ? Glass.buy : Glass.sell).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DerivSymbols.display(h.symbol)).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                                Text("\(dateStr(h.sellTime)) · \(h.contractType.uppercased().contains("UP") ? "UP" : "DOWN")")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Text(String(format: "%@%.2f", h.profit > 0 ? "+" : "", h.profit))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(h.profit > 0 ? Glass.buy : Glass.sell)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        if idx < app.history.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                    }
                }
                .glassCard()
            }
        }
    }

    // MARK: Generated signals with PERFORMANCE TRACKING
    private var signalsPerformanceSection: some View {
        VStack(spacing: 14) {
            // Performance summary cards
            performanceSummaryCards

            // Active signals
            if !performance.activeSignals().isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active Signals").font(.caption).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text("\(performance.activeSignals().count) tracking")
                            .font(.caption).foregroundStyle(Glass.accent2)
                    }
                    ForEach(performance.activeSignals().prefix(10)) { tracked in
                        ActiveSignalRow(tracked: tracked)
                    }
                }
            }

            // Resolved signals (TP/SL hit)
            let resolved = performance.resolvedSignals().prefix(20)
            if !resolved.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Resolved Signals").font(.caption).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text("\(performance.resolvedSignals().count) total")
                            .font(.caption).foregroundStyle(.white.opacity(0.4))
                    }
                    ForEach(Array(resolved)) { tracked in
                        ResolvedSignalRow(tracked: tracked)
                    }
                }
            }

            // Recommendations
            let recs = performance.recommendations()
            if recs.count > 1 || (recs.count == 1 && !recs[0].contains("Need at least")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Insights").font(.caption).foregroundStyle(.white.opacity(0.5))
                    ForEach(recs, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Glass.accent2)
                            Text(rec)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding(12)
                .glassCard()
            }

            if signalLog.signals.isEmpty && performance.trackedSignals.isEmpty {
                EmptyState(icon: "waveform.path.ecg",
                           title: "No signals recorded yet",
                           subtitle: "As the council generates signals they are tracked here in real time — performance is monitored automatically.")
            }

            // Actions
            HStack {
                if !signalLog.signals.isEmpty {
                    Button("Clear History") { signalLog.clear() }
                        .font(.caption).foregroundStyle(Glass.sell)
                }
                Spacer()
                if !performance.trackedSignals.isEmpty {
                    Button("Reset Performance") { performance.clear() }
                        .font(.caption).foregroundStyle(Glass.sell.opacity(0.7))
                }
            }
        }
    }

    private var performanceSummaryCards: some View {
        let resolved = performance.resolvedSignals()
        let wr = resolved.isEmpty ? 0 : Int(performance.overallWinRate * 100)
        let wins = resolved.filter { $0.isWin }.count
        let losses = resolved.count - wins

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                StatCard(value: "\(wr)%", label: "Win rate", color: .white)
                StatCard(value: "\(wins)", label: "Wins", color: Glass.buy)
                StatCard(value: "\(losses)", label: "Losses", color: Glass.sell)
            }
            if resolved.count >= 5 {
                HStack(spacing: 12) {
                    let rr = performance.averageRR
                    StatCard(value: String(format: "%.1f", rr), label: "Avg R:R", color: Glass.accent2)
                    StatCard(value: "\(resolved.count)", label: "Total", color: .white.opacity(0.7))
                    StatCard(value: "\(performance.activeSignals().count)", label: "Active", color: .yellow)
                }
            }
        }
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"; return f.string(from: d)
    }
}

// MARK: - Active Signal Row

struct ActiveSignalRow: View {
    let tracked: TrackedSignal

    var body: some View {
        HStack(spacing: 10) {
            // Direction indicator
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tracked.signal.isBuy ? Glass.buy.opacity(0.2) : Glass.sell.opacity(0.2))
                Text(tracked.signal.isBuy ? "B" : "S")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tracked.signal.isBuy ? Glass.buy : Glass.sell)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(tracked.signal.displayPair)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                HStack(spacing: 6) {
                    Text("Entry \(fmt(tracked.entryPrice))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("SL \(fmt(tracked.signal.stopLoss))")
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.sell.opacity(0.6))
                    Text("TP \(fmt(tracked.signal.takeProfit))")
                        .font(.system(size: 10))
                        .foregroundStyle(Glass.buy.opacity(0.6))
                }
            }

            Spacer()

            // Floating P&L
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt(tracked.floatingPnL))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tracked.floatingPnL >= 0 ? Glass.buy : Glass.sell)
                Text("\(Int(tracked.signal.confidence))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(10)
        .glassCard()
    }

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.1f", v) : String(format: "%.4f", v)
    }
}

// MARK: - Resolved Signal Row

struct ResolvedSignalRow: View {
    let tracked: TrackedSignal

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(0.2))
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tracked.signal.displayPair)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    Text(fmt(tracked.floatingPnL))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tracked.floatingPnL >= 0 ? Glass.buy : Glass.sell)
                }
                HStack(spacing: 6) {
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                    if let exitTime = tracked.exitTime {
                        Text(dateStr(exitTime))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if let holding = tracked.holdingTime {
                        Text(formatDuration(holding))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(10)
        .glassCard()
    }

    private var statusColor: Color {
        switch tracked.status {
        case .hitTakeProfit: return Glass.buy
        case .hitStopLoss: return Glass.sell
        case .expired: return .orange
        default: return .white.opacity(0.5)
        }
    }

    private var statusIcon: String {
        switch tracked.status {
        case .hitTakeProfit: return "checkmark.circle.fill"
        case .hitStopLoss: return "xmark.circle.fill"
        case .expired: return "clock.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusLabel: String {
        switch tracked.status {
        case .hitTakeProfit: return "TP HIT"
        case .hitStopLoss: return "SL HIT"
        case .expired: return "EXPIRED"
        default: return "UNKNOWN"
        }
    }

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.1f", v) : String(format: "%.4f", v)
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"; return f.string(from: d)
    }

    private func formatDuration(_ ti: TimeInterval) -> String {
        let mins = Int(ti / 60)
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }
}

struct StatCard: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(color.opacity(0.95))
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .glassCard()
    }
}
