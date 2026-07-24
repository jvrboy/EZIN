import SwiftUI

/// Consolidated trading dashboard — watchlist prices, P&L overview, recent activity
struct TradingDashboardView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var feed = NewsFeedService.shared
    @ObservedObject private var journal = TradeJournalStore.shared

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Welcome / Status Header
                    welcomeSection

                    // MARK: - Quick Stats Grid
                    statsGrid

                    // MARK: - Watchlist Prices
                    watchlistSection

                    // MARK: - Recent Trades
                    recentTradesSection

                    // MARK: - Breaking News
                    breakingNewsSection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Welcome Header

    private var welcomeSection: some View {
        GlassSection(title: "Overview") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Connection status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(app.connectionState == .connected ? Glass.buy : (app.connectionState == .connecting ? .yellow : Glass.sell))
                            .frame(width: 8, height: 8)
                        Text(app.connectionState.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Text("Good \(timeOfDay), Trader")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 2)

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Trading session indicator
                VStack(spacing: 4) {
                    Image(systemName: sessionIcon)
                        .font(.system(size: 22))
                        .foregroundStyle(sessionColor)
                    Text(sessionLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            // Win Rate
            StatCard(
                icon: "target",
                label: "Win Rate",
                value: winRateText,
                color: Glass.buy,
                trend: .up
            )

            // Active Signals
            StatCard(
                icon: "waveform.path.ecg",
                label: "Signals",
                value: "\(app.signals.count)",
                color: Glass.accent2,
                trend: .neutral
            )

            // Open Trades
            StatCard(
                icon: "chart.line.uptrend.xyaxis",
                label: "Journal",
                value: "\(journal.entries.count)",
                color: Glass.accent,
                trend: .neutral
            )

            // Trade History
            StatCard(
                icon: "clock.arrow.circlepath",
                label: "Trades",
                value: "\(app.history.count)",
                color: .orange,
                trend: .neutral
            )

            // Bot Status
            StatCard(
                icon: "cpu",
                label: "Bot",
                value: app.bot.running ? "Active" : "Off",
                color: app.bot.running ? Glass.buy : .white.opacity(0.5),
                trend: app.bot.running ? .up : .neutral
            )

            // News Alerts
            StatCard(
                icon: "newspaper",
                label: "News",
                value: "\(feed.newsItems.filter { $0.impact == .critical || $0.impact == .high }.count)",
                color: .yellow,
                trend: .neutral
            )
        }
    }

    // MARK: - Watchlist Prices

    private var watchlistSection: some View {
        GlassSection(title: "Watchlist Prices") {
            if app.settings.watchlist.isEmpty {
                VStack(spacing: 8) {
                    Text("No instruments in your watchlist")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                    Text("Add symbols in Settings or ask the chat assistant")
                        .font(.caption2).foregroundStyle(.white.opacity(0.3))
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(app.settings.watchlist.prefix(8)), id: \.self) { symbol in
                    watchlistRow(symbol: symbol)
                    if symbol != app.settings.watchlist.prefix(8).last {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }

    private func watchlistRow(symbol: String) -> some View {
        HStack(spacing: 12) {
            // Symbol icon
            Circle()
                .fill(assetColor(for: symbol).opacity(0.2))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(symbol.prefix(2))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(assetColor(for: symbol))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(DerivSymbols.assetClass(symbol).rawValue.capitalized)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            // Price
            if let price = livePrice(symbol) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceText(price, symbol: symbol))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(changeText(symbol))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(changeColor(symbol))
                }
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Open chart")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Recent Trades

    private var recentTradesSection: some View {
        let recent: [JournalEntry] = Array(journal.entries.sorted(by: { $0.entryDate > $1.entryDate }).prefix(5))
        return GlassSection(title: "Recent Journal Entries") {
            if recent.isEmpty {
                VStack(spacing: 8) {
                    Text("No journal entries yet")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                    Text("Log your first trade in the Trade Journal or ask the chat")
                        .font(.caption2).foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(recent, id: \.id) { (entry: JournalEntry) in
                    HStack(spacing: 12) {
                        // Direction badge
                        VStack(spacing: 2) {
                            Image(systemName: entry.direction.isBullish ? "arrow.up" : "arrow.down")
                                .font(.system(size: 12, weight: .bold))
                            Text(entry.direction.isBullish ? "BUY" : "SELL")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(entry.direction.isBullish ? Glass.buy : Glass.sell)
                        .frame(width: 28, height: 28)
                        .background((entry.direction.isBullish ? Glass.buy : Glass.sell).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("\(entry.quantity, specifier: "%.2f") @ \(entry.entryPrice, specifier: "%.5f")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }

                        Spacer()

                        // P&L if closed
                        VStack(alignment: .trailing, spacing: 1) {
                            if let exit = entry.exitPrice {
                                Text(pnlText(entry: entry, exit: exit))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(pnlColor(entry: entry, exit: exit))
                                Text("Closed")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.3))
                            } else {
                                Text("Open")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Glass.accent2.opacity(0.7))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    if entry.id != recent.last?.id {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }

    // MARK: - Breaking News

    private var breakingNewsSection: some View {
        let critical = feed.newsItems
            .filter { $0.impact == .critical || $0.impact == .high }
            .sorted(by: { $0.publishedAt > $1.publishedAt })
            .prefix(3)

        return Group {
            if !critical.isEmpty {
                GlassSection(title: "Breaking") {
                    ForEach(Array(critical), id: \.id) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.sentiment.score > 0 ? Glass.buy : (item.sentiment.score < 0 ? Glass.sell : .yellow))
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                                .pulsating()

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.source)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Glass.accent2.opacity(0.7))
                                    Text(item.impact.rawValue.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(item.impact == .critical ? Glass.sell : .orange)
                                }
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        if item.id != critical.last?.id {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private var sessionLabel: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "Asia / Sydney"
        case 6..<12: return "London Open"
        case 12..<16: return "London / NY"
        case 16..<21: return "New York"
        default: return "Asia Prelude"
        }
    }

    private var sessionIcon: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "sun.max.fill"
        case 6..<12: return "sunrise.fill"
        case 12..<16: return "sun.max.fill"
        case 16..<21: return "sunset.fill"
        default: return "moon.fill"
        }
    }

    private var sessionColor: Color {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return .orange.opacity(0.7)
        case 6..<12: return .yellow
        case 12..<16: return .white
        case 16..<21: return .orange
        default: return Glass.accent2.opacity(0.6)
        }
    }

    private var winRateText: String {
        let resolved = journal.entries.filter { $0.exitPrice != nil }
        guard !resolved.isEmpty else { return "—" }
        let wins = resolved.filter { entry in
            guard let exit = entry.exitPrice else { return false }
            return entry.direction.isBullish ? exit > entry.entryPrice : exit < entry.entryPrice
        }
        return "\(Int(Double(wins.count) / Double(resolved.count) * 100))%"
    }

    private func livePrice(_ symbol: String) -> Double? {
        app.deriv.prices[symbol] ?? app.deriv.priceCache[symbol]?.prices.last
    }

    private func priceText(_ price: Double, symbol: String) -> String {
        price > 100 ? String(format: "%.2f", price) : String(format: "%.5f", price)
    }

    private func changeText(_ symbol: String) -> String {
        guard let prices = app.deriv.priceCache[symbol]?.prices, prices.count >= 2 else {
            return "+0.00"
        }
        let change = prices.last! - prices[prices.count - 2]
        return (change >= 0 ? "+" : "") + String(format: "%.4f", change)
    }

    private func changeColor(_ symbol: String) -> Color {
        guard let prices = app.deriv.priceCache[symbol]?.prices, prices.count >= 2 else {
            return .white.opacity(0.3)
        }
        return prices.last! >= prices[prices.count - 2] ? Glass.buy : Glass.sell
    }

    private func assetColor(for symbol: String) -> Color {
        switch DerivSymbols.assetClass(symbol) {
        case .synthetic: return .purple
        case .forex: return .blue
        case .crypto: return .orange
        case .commodity: return .yellow
        case .index: return .green
        }
    }

    private func pnlText(entryPrice: Double, direction: String, quantity: Double, exit: Double) -> String {
        let pnl: Double
        if direction == "buy" {
            pnl = (exit - entryPrice) * quantity
        } else {
            pnl = (entryPrice - exit) * quantity
        }
        return (pnl >= 0 ? "+" : "") + String(format: "%.2f", pnl)
    }

    private func pnlColor(entryPrice: Double, direction: String, exit: Double) -> Color {
        let pnl: Double
        if direction == "buy" {
            pnl = (exit - entryPrice) * entryPrice
        } else {
            pnl = (entryPrice - exit) * entryPrice
        }
        return pnl >= 0 ? Glass.buy : Glass.sell
    }

    // Convenience overloads that read the direction/quantity/entryPrice from a JournalEntry
    // (JournalEntry.direction is a Direction enum, not a String).
    private func pnlText(entry: JournalEntry, exit: Double) -> String {
        let pnl: Double = entry.direction.isBullish
            ? (exit - entry.entryPrice) * entry.quantity
            : (entry.entryPrice - exit) * entry.quantity
        return (pnl >= 0 ? "+" : "") + String(format: "%.2f", pnl)
    }

    private func pnlColor(entry: JournalEntry, exit: Double) -> Color {
        let pnl: Double = entry.direction.isBullish
            ? (exit - entry.entryPrice)
            : (entry.entryPrice - exit)
        return pnl >= 0 ? Glass.buy : Glass.sell
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let trend: Trend

    enum Trend { case up, down, neutral }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(height: 20)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 3) {
                if trend != .neutral {
                    Image(systemName: trend == .up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(color.opacity(trend == .neutral ? 0.5 : 0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .glassCard(corner: 16)
    }
}

// MARK: - Pulsating modifier

fileprivate struct PulsatingModifier: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.1 : 1.0)
            .opacity(pulse ? 0.7 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
    }
}

fileprivate extension View {
    func pulsating() -> some View {
        modifier(PulsatingModifier())
    }
}
