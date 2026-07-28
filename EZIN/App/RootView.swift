import SwiftUI

/// Root shell — collapsible sidebar navigation with hamburger toggle.
/// Replaces the old bottom tab bar with a slide-out side panel for more screen real estate.
struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .chart
    @State private var showSidebar = false
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                VStack(spacing: 0) {
                    header
                    Group {
                        switch tab {
                        case .dashboard: TradingDashboardView(deriv: app.deriv)
                        case .chart:    ChartView()
                        case .signals:  SignalsView()
                        case .games:    GamesView()
                        case .chat:     ChatView()
                        case .history:  HistoryView(bot: app.bot)
                        case .bot:      BotView(bot: app.bot)
                        case .tools:    ToolsHubView()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .font(theme.fontStyle.font)
            // Sidebar overlay
            .overlay(
                ZStack(alignment: .leading) {
                    // Dim background — tap to dismiss
                    if showSidebar {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showSidebar = false
                                }
                            }
                    }

                    // Sidebar panel
                    if showSidebar {
                        SidebarView(selection: $tab, isOpen: $showSidebar)
                            .frame(width: 260)
                            .transition(.move(edge: .leading))
                    }
                }
            )
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                if app.settings.signalScanningEnabled { app.bot.startScanning() }
            case .background, .inactive:
                app.bot.stopScanning()
            @unknown default:
                app.bot.stopScanning()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Hamburger button — toggles sidebar
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Text("EZIN")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Show current tab name
            Text(tab.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()
            ConnectionPill(state: app.connectionState)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - Tab Model

enum AppTab: String, CaseIterable {
    case dashboard, chart, signals, games, chat, history, bot, tools, settings
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
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
        case .dashboard: return "square.grid.2x2.fill"
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

// MARK: - Sidebar

/// Slide-out sidebar with all navigation items. Tap an item to switch tabs; the sidebar
/// auto-dismisses. The active tab is highlighted with an accent pill.
struct SidebarView: View {
    @Binding var selection: AppTab
    @Binding var isOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Brand header
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Glass.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EZIN")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Signal Intelligence")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isOpen = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.08))

            // Navigation items
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(AppTab.allCases, id: \.self) { t in
                        sidebarRow(t)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)

            // Footer
            VStack(spacing: 6) {
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 6, height: 6)
                    Text("v1.8.1")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                    Text(DerivClient.defaultAppID.description)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.14), Color(red: 0.05, green: 0.05, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.white.opacity(0.08))
                .frame(maxWidth: .infinity, alignment: .trailing)
        )
    }

    private func sidebarRow(_ t: AppTab) -> some View {
        let isActive = selection == t
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selection = t
                isOpen = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: t.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28)
                    .foregroundStyle(isActive ? Glass.accent : .white.opacity(0.5))

                Text(t.title)
                    .font(.system(size: 15, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.6))

                Spacer()

                if isActive {
                    Circle()
                        .fill(Glass.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var connectionColor: Color {
        .green  // sidebar footer uses static color; live status shown in header pill
    }
}

// MARK: - Legacy (kept for any external references)

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

                    GlassSection(title: "Market News") {
                        NavigationLink(destination: NewsFeedView()) {
                            GlassNavRow(icon: "newspaper.fill", title: "Market News Feed",
                                        value: "\(NewsFeedService.shared.newsItems.count) articles")
                        }.buttonStyle(.plain)
                    }

                    GlassSection(title: "Alerts") {
                        NavigationLink(destination: AlertCenterView()) {
                            GlassNavRow(icon: "bell.badge.fill", title: "Alert Center",
                                        value: "\(AlertStore.shared.configurations.count) configured")
                        }.buttonStyle(.plain)
                    }

                    GlassSection(title: "About") {
                        VStack(spacing: 8) {
                            Text("Tools Hub")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Log your trades, track economic events, calculate position sizes, and browse market news — all on-device.")
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
