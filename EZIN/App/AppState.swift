import SwiftUI
import Combine

/// Central observable app state. Owns the hidden backend runtime and shared stores.
@MainActor
final class AppState: ObservableObject {
    // Stores
    let settings = SettingsStore.shared
    let credentials = CredentialStore.shared
    let models = LLMModelStore.shared
    let pipelines = PipelineStore.shared

    // Runtime
    let deriv = DerivClient()
    let engine = SignalEngine()
    lazy var botRuntime = BotRuntime(deriv: deriv, engine: engine)

    // Published UI feeds
    @Published var signals: [TradingSignal] = []
    @Published var history: [SignalOutcome] = []
    @Published var connectionState: DerivConnectionState = .disconnected
    @Published var booted = false

    private var bag = Set<AnyCancellable>()

    func boot() async {
        guard !booted else { return }
        booted = true

        // Wire Deriv connection state to UI.
        deriv.$connectionState
            .receive(on: RunLoop.main)
            .assign(to: &$connectionState)

        // Bots + agents run hidden in the backend; they publish signals to the UI.
        botRuntime.onSignals = { [weak self] signals in
            Task { @MainActor in self?.signals = signals }
        }
        botRuntime.onOutcome = { [weak self] outcome in
            Task { @MainActor in self?.history.insert(outcome, at: 0) }
        }

        history = HistoryStore.shared.load()

        // Connect using default public Deriv app id, or the user's custom one.
        let appID = settings.derivAppID
        let token = credentials.value(for: .derivToken)
        await deriv.connect(appID: appID, token: token)

        // Start the always-on backend loop.
        await botRuntime.start(symbols: settings.watchlist)
    }

    func restartBackend() {
        Task {
            await botRuntime.stop()
            let appID = settings.derivAppID
            let token = credentials.value(for: .derivToken)
            await deriv.connect(appID: appID, token: token)
            await botRuntime.start(symbols: settings.watchlist)
        }
    }
}
