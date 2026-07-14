import SwiftUI

/// EZIN — Deriv signal intelligence, glass edition.
/// Native SwiftUI port of the forex-signals / forex-jsx / multi-agent bot suite.
@main
struct EZINApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var theme = ThemeStore.shared

    init() {
        // Create the app's own on-device directory (surfaced in the Files app)
        FileStore.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .font(theme.typeface.appFont)
                .dynamicTypeSize(theme.textScale.dynamicTypeSize)
                .preferredColorScheme(.dark)
                .task {
                    // Boot the hidden backend runtime (agents, council, bots, pipelines)
                    await appState.boot()
                }
        }
    }
}
