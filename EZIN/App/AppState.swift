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

    private var historyTimer: Timer?
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

        await connect()
        bot.startScanning()

        // Refresh real closed-trade history periodically.
        await refreshHistory()
        historyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refreshHistory() }
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
