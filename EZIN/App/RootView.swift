import SwiftUI

/// Root shell — glass tab bar: Chart · Signals · Games · Chat · History · Bot · Tools · Settings.
struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: AppTab = .chart
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header
                Group {
                    switch tab {
                    case .chart:    ChartView()
                    case .signals:  SignalsView()
                    case .games:    GamesView()
                    case .chat:     ChatView()
                    case .history:  HistoryView()
                    case .bot:      BotView()
                    case .tools:    ToolsHubView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

                GlassTabBar(selection: $tab)
            }
        }
        .font(theme.fontStyle.font)
    }

    private var header: some View {
        HStack {
            Text("EZIN")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            ConnectionPill(state: app.connectionState)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

enum AppTab: String, CaseIterable {
    case chart, signals, games, chat, history, bot, tools, settings
    var title: String {
        switch self {
        case .chart:    return "Chart"
        case .signals:  return "Signals"
        case .games:    return "Games"
        case .chat:     return "Chat"
        case .history:  return "History"
        case .bot:      return "Bot"
        case .tools:    return "Tools"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .chart:    return "chart.xyaxis.line"
        case .signals:  return "waveform.path.ecg"
        case .games:    return "gamecontroller.fill"
        case .chat:     return "bubble.left.and.bubble.right"
        case .history:  return "clock.arrow.circlepath"
        case .bot:      return "cpu"
        case .tools:    return "wrench.and.screwdriver.fill"
        case .settings: return "gearshape"
        }
    }
}

struct GlassTabBar: View {
    @Binding var selection: AppTab
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = t }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .semibold))
                        Text(t.title).font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selection == t ? .white : .white.opacity(0.45))
                    .background(
                        RoundedRectangle(cornerRadius: Glass.cornerSmall, style: .continuous)
                            .fill(selection == t ? Color.white.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassCard(strong: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Tools Hub (Journal · Calendar · Calculator)

struct ToolsHubView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    GlassSection(title: "Trading Journal") {
                        NavigationLink(destination: TradeJournalView()) {
                            GlassNavRow(icon: "book.fill", title: "Trade Journal",
                                        value: "\(TradeJournalStore.shared.entries.count) entries")
                        }.buttonStyle(.plain)
                    }

                    GlassSection(title: "Market Data") {
                        NavigationLink(destination: EconomicCalendarView()) {
                            GlassNavRow(icon: "calendar.badge.clock", title: "Economic Calendar",
                                        value: "\(EconomicCalendarService.shared.highImpactEvents.count) high impact")
                        }.buttonStyle(.plain)
                    }

                    GlassSection(title: "Calculators") {
                        NavigationLink(destination: PositionCalculatorView()) {
                            GlassNavRow(icon: "function", title: "Position & Risk Calculator",
                                        value: "Size, P&L, Pip")
                        }.buttonStyle(.plain)
                    }

                    GlassSection(title: "About") {
                        VStack(spacing: 8) {
                            Text("Tools Hub")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Log your trades, track economic events, and calculate position sizes — all on-device.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 8)
                    }

                    Text("Ask the chat assistant about any tool — e.g. 'log a trade' or 'what economic events are coming'".uppercased())
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

struct ConnectionPill: View {
    let state: DerivConnectionState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(state.label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassCard(corner: 999)
    }
    private var color: Color {
        switch state {
        case .connected: return Glass.buy
        case .connecting: return .yellow
        case .disconnected, .error: return Glass.sell
        }
    }
}
