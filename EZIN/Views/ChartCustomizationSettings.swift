import Foundation
import SwiftUI

/// Chart customization settings for Volume Profile, Heatmap, and Jump detection sensitivity
struct ChartCustomizationSettings: Codable {
    /// Volume Profile bin count (12-48, default 24)
    var volumeProfileBins: Int = 24
    /// Volume Profile value area percentage (60-80%, default 70%)
    var volumeProfileVA: Double = 0.70
    /// Show Volume Profile on chart (default true)
    var showVolumeProfile: Bool = true

    /// Heatmap sensitivity multiplier (0.5-2.0, default 1.0)
    /// Higher = more levels shown, lower = only strong levels
    var heatmapSensitivity: Double = 1.0
    /// Heatmap max levels to display (3-10, default 6)
    var heatmapMaxLevels: Int = 6
    /// Show Heatmap on chart (default true)
    var showHeatmap: Bool = true

    /// Jump detection MAD multiplier (2.0-5.0, default 3.0)
    /// Higher = only major jumps detected, lower = more sensitive
    var jumpSensitivity: Double = 3.0
    /// Jump lookback period in candles (60-240, default 120)
    var jumpLookback: Int = 120
    /// Show Jump markers on chart (default true)
    var showJumpMarkers: Bool = true

    /// Price chart candle count for lookback (100-1000, default 500)
    var candleLookback: Int = 500

    static let storageKey = "chartCustomization.v1"

    /// Validate and clamp all settings to valid ranges
    mutating func validate() {
        volumeProfileBins = max(12, min(48, volumeProfileBins))
        volumeProfileVA = max(0.6, min(0.8, volumeProfileVA))
        heatmapSensitivity = max(0.5, min(2.0, heatmapSensitivity))
        heatmapMaxLevels = max(3, min(10, heatmapMaxLevels))
        jumpSensitivity = max(2.0, min(5.0, jumpSensitivity))
        jumpLookback = max(60, min(240, jumpLookback))
        candleLookback = max(100, min(1000, candleLookback))
    }
}

/// Persisted chart customization store
final class ChartCustomizationStore: ObservableObject {
    static let shared = ChartCustomizationStore()
    @Published var settings: ChartCustomizationSettings {
        didSet { save() }
    }
    private let d = UserDefaults.standard

    private init() {
        if let data = d.data(forKey: ChartCustomizationSettings.storageKey),
           let cfg = try? JSONDecoder().decode(ChartCustomizationSettings.self, from: data) {
            settings = cfg
            settings.validate()
        } else {
            settings = ChartCustomizationSettings()
        }
    }

    private func save() {
        // Clamp on a local copy so validation never re-enters @Published.didSet.
        var snapshot = settings
        snapshot.validate()
        if let data = try? JSONEncoder().encode(snapshot) {
            d.set(data, forKey: ChartCustomizationSettings.storageKey)
        }
    }

    /// Reset to defaults
    func reset() {
        settings = ChartCustomizationSettings()
    }

    /// Preset: Aggressive (more sensitive)
    func applyAggressivePreset() {
        settings.volumeProfileBins = 16
        settings.heatmapSensitivity = 1.5
        settings.jumpSensitivity = 2.5
    }

    /// Preset: Conservative (less sensitive)
    func applyConservativePreset() {
        settings.volumeProfileBins = 32
        settings.heatmapSensitivity = 0.7
        settings.jumpSensitivity = 4.0
    }
}

// MARK: - Chart Settings View Extension

extension ChartCustomizationStore {
    /// Returns a View for chart customization settings
    @ViewBuilder
    func settingsView() -> some View {
        ChartCustomizationView()
    }
}

/// SwiftUI View for Chart Customization Settings
struct ChartCustomizationView: View {
    @ObservedObject private var store = ChartCustomizationStore.shared
    @State private var showingPresets = false

    var body: some View {
        Form {
            Section(header: Text("Volume Profile")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bin Count: \(store.settings.volumeProfileBins)")
                        Spacer()
                        Text("Sensitivity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(store.settings.volumeProfileBins) },
                            set: { store.settings.volumeProfileBins = Int($0) }
                        ),
                        in: 12...48,
                        step: 4
                    )
                    .onChange(of: store.settings.volumeProfileBins) { _ in
                        store.objectWillChange.send()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Value Area: \(Int(store.settings.volumeProfileVA * 100))%")
                        Spacer()
                        Text("70% Standard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $store.settings.volumeProfileVA,
                        in: 0.6...0.8,
                        step: 0.02
                    )
                }

                Toggle("Show Volume Profile", isOn: $store.settings.showVolumeProfile)
            }

            Section(header: Text("Heatmap (Liquidity Levels)")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sensitivity: \(String(format: "%.1f", store.settings.heatmapSensitivity))x")
                        Spacer()
                        Text(store.settings.heatmapSensitivity < 1.0 ? "Less Sensitive" :
                             store.settings.heatmapSensitivity > 1.0 ? "More Sensitive" : "Default")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $store.settings.heatmapSensitivity, in: 0.5...2.0, step: 0.1)
                }

                Stepper("Max Levels: \(store.settings.heatmapMaxLevels)", value: $store.settings.heatmapMaxLevels, in: 3...10)

                Toggle("Show Heatmap", isOn: $store.settings.showHeatmap)
            }

            Section(header: Text("Jump Detection")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("MAD Multiplier: \(String(format: "%.1f", store.settings.jumpSensitivity))")
                        Spacer()
                        Text(store.settings.jumpSensitivity < 3.0 ? "Sensitive" :
                             store.settings.jumpSensitivity > 3.0 ? "Major Only" : "Default")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $store.settings.jumpSensitivity, in: 2.0...5.0, step: 0.5)
                }

                Stepper("Lookback: \(store.settings.jumpLookback) candles", value: $store.settings.jumpLookback, in: 60...240, step: 20)

                Toggle("Show Jump Markers", isOn: $store.settings.showJumpMarkers)
            }

            Section(header: Text("Presets")) {
                Button("Aggressive (More Sensitive)") {
                    store.applyAggressivePreset()
                }
                .foregroundColor(.orange)

                Button("Conservative (Less Sensitive)") {
                    store.applyConservativePreset()
                }
                .foregroundColor(.blue)

                Button("Reset to Defaults") {
                    store.reset()
                }
                .foregroundColor(.red)
            }

            Section(header: Text("About")) {
                HStack {
                    Text("Volume Profile")
                    Spacer()
                    Text("Price levels with highest volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Heatmap")
                    Spacer()
                    Text("Liquidity clusters & support/resistance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Jump Detection")
                    Spacer()
                    Text("Unusual price movements (MAD-based)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Chart View Model Integration

extension ChartViewModel {
    /// Apply customization settings to chart indicators
    func applyCustomizationSettings() {
        let settings = ChartCustomizationStore.shared.settings
        showVolumeProfile = settings.showVolumeProfile
        showHeatmap = settings.showHeatmap
        showMarkers = settings.showJumpMarkers
    }

    /// Reload indicators with custom settings
    func reloadWithCustomization() async {
        guard let deriv = deriv, !loading else { return }
        loading = true
        defer { loading = false }

        let settings = ChartCustomizationStore.shared.settings

        if let c = try? await deriv.candles(symbol: symbol, timeframe: timeframe, count: settings.candleLookback) {
            candles = c
            lastPrice = c.last?.close

            let marketData = MarketData(candles: c)

            // Volume Profile with custom settings
            volumeProfileData = Microstructure.volumeProfile(
                high: marketData.highs,
                low: marketData.lows,
                close: marketData.closes,
                volume: marketData.volumes,
                bins: settings.volumeProfileBins
            )

            // Liquidity Heatmap with custom sensitivity
            let adjustedMaxLevels = Int(Double(settings.heatmapMaxLevels) * settings.heatmapSensitivity)
            liquidityLevels = Microstructure.liquidityLevels(
                high: marketData.highs,
                low: marketData.lows,
                close: marketData.closes,
                lookback: settings.jumpLookback,
                maxLevels: adjustedMaxLevels
            )

            // Jump Detection with custom sensitivity
            jumpEvents = Microstructure.detectJumps(
                marketData.closes,
                mult: settings.jumpSensitivity,
                lookback: settings.jumpLookback
            )
        }
    }
}
