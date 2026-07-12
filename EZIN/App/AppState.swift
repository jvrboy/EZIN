import SwiftUI
import Combine

/// Central observable app state. Owns the real Deriv client, signal engine and trading bot.
@MainActor
final class AppState: ObservableObject {
    // Stores
    let settings = SettingsStore.shared
    let credentials = CredentialStore.shared
    let models = LLMModelStore.shared
    let pipelines = PipelineStore.shared
    let botConfig = BotConfigStore.shared

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

    func boot() async {
        guard !booted else { return }
        booted = true

        deriv.$connectionState.receive(on: RunLoop.main).assign(to: &$connectionState)

        bot.onSignals = { [weak self] signals in
            Task { @MainActor in self?.signals = signals }
        }

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
