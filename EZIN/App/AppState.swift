import SwiftUI
import Combine

/// Central observable app state. Owns the real Deriv client, signal engine and trading bot.
@MainActor
final class AppState: ObservableObject {
    // Stores
    let settings = SettingsStore.shared
    let credentials = CredentialStore.shared
    let apiKeys = APIKeyStore.shared
    let models = LLMModelStore.shared
    let pipelines = PipelineStore.shared
    let botConfig = BotConfigStore.shared
    let signalHistory = SignalHistoryStore.shared
    let signalPerformance = SignalPerformanceStore.shared
    let brain = BrainEngine.shared

    // Runtime
    let deriv = DerivClient()
    let engine = SignalEngine()
    lazy var bot = BotRuntime(deriv: deriv, engine: engine)

    // Published UI feeds
    @Published var signals: [TradingSignal] = []
    @Published var history: [DerivClosedTrade] = []
    @Published var connectionState: DerivConnectionState = .disconnected
    @Published var booted = false
    @Published var lastAutoRefreshAt: Date?

    private var historyTimer: Timer?
    private var autoRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func boot() async {
        guard !booted else { return }
        booted = true

        deriv.$connectionState.receive(on: RunLoop.main).assign(to: &$connectionState)

        // Push notifications: request authorization on first boot.
        Task { await PushNotificationManager.shared.requestAuthorization() }

        // Wire signal feeds: history + performance tracking + push notifications.
        bot.onSignals = { [weak self] signals in
            Task { @MainActor in
                self?.signals = signals
                self?.signalHistory.record(signals)
                // Track performance for each new signal.
                for signal in signals {
                    let price = self?.deriv.prices[signal.symbol] ?? signal.entry
                    self?.signalPerformance.track(signal, currentPrice: price)
                }
                // Notify for high-confidence signals.
                for signal in signals where signal.confidence >= 75 {
                    PushNotificationManager.shared.notifySignalGenerated(signal)
                }
            }
        }

        // Wire price updates to performance tracking.
        deriv.$prices
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] prices in
                Task { @MainActor in
                    self?.signalPerformance.updatePrices(prices)
                }
            }
            .store(in: &cancellables)

        // Wire push notifications to connection state changes.
        deriv.$connectionState
            .dropFirst()
            .sink { state in
                switch state {
                case .error: PushNotificationManager.shared.notifyConnectionLost()
                case .connected: PushNotificationManager.shared.notifyConnectionRestored()
                default: break
                }
            }
            .store(in: &cancellables)

        applyDisabledAgents()
        await connect()
        bot.startScanning()
        BackgroundRefreshManager.shared.configure(app: self)
        startAutoRefresh()

        // Refresh real closed-trade history periodically.
        await refreshHistory()
        historyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refreshHistory() }
        }
    }

    /// Whole-app foreground heartbeat: every 5 seconds the backend refreshes live state,
    /// heals a dropped socket, re-subscribes symbols and updates tracked signal outcomes.
    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { await self?.refreshRealtime() }
        }
    }

    func refreshRealtime() async {
        lastAutoRefreshAt = Date()
        switch deriv.connectionState {
        case .disconnected, .error:
            await connect()
        case .connected:
            // Re-assert subscriptions in case Deriv dropped one stream after a reconnect.
            for symbol in deriv.subscribedSymbolsSnapshot { deriv.subscribeTicks(symbol) }
        case .connecting:
            break
        }
        signalPerformance.updatePrices(deriv.prices)
    }

    private func applyDisabledAgents() {
        let disabled = Set(settings.disabledAgentNames)
        for i in engine.agents.indices {
            engine.agents[i].isActive = !disabled.contains(engine.agents[i].name)
        }
    }

    func connect() async {
        let appID = settings.useCustomDeriv ? settings.derivAppID : DerivClient.defaultAppID
        let token = credentials.value(for: .derivToken)
        await deriv.connect(appID: appID, token: token)
    }

    func refreshHistory() async {
        guard deriv.authorized else { return }
        if let trades = try? await deriv.profitTable(limit: 50) {
            history = trades
        }
    }

    func restartBackend() {
        Task {
            let wasRunning = bot.running
            bot.stopBot()
            deriv.disconnect()
            await connect()
            await refreshHistory()
            if wasRunning { bot.startBot() }
        }
    }
}
