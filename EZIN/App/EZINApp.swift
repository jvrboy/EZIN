import SwiftUI

/// EZIN — Deriv signal intelligence, glass edition.
/// Native SwiftUI port of the forex-signals / forex-jsx / multi-agent bot suite.
@main
struct EZINApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Create the app's own on-device directory (surfaced in the Files app)
        FileStore.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .task {
                    // Boot the hidden backend runtime (agents, council, bots, pipelines)
                    await appState.boot()
                }
        }
    }
}
