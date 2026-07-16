import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var apiKeys = APIKeyStore.shared

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        GlassSection(title: "Assistant") {
                            NavigationLink { ChatSettingsView() } label: {
                                GlassNavRow(icon: "bubble.left.and.bubble.right.fill", title: "Chat, agents & MCP",
                                            value: "\(AgentRegistry.agents.count) agents")
                            }.buttonStyle(.plain)
                        }

                        GlassSection(title: "Trading Bot") {
                            NavigationLink { BotSettingsView() } label: {
                                GlassNavRow(icon: "cpu", title: "Bot configuration",
                                            value: "\(app.botConfig.config.instruments.count) instruments")
                            }.buttonStyle(.plain)
                            Divider().overlay(Color.white.opacity(0.08))
                            NavigationLink { RegimeFilterSettingsView() } label: {
                                GlassNavRow(icon: "waveform.path.ecg", title: "Regime Filtering",
                                            value: RegimeAwareSignalFilter.shared.config.enabled ? "Enabled" : "Disabled")
                            }.buttonStyle(.plain)
                        }

                        GlassSection(title: "Appearance") {
                            NavigationLink { AppearanceView() } label: {
                                GlassNavRow(icon: "paintbrush.fill", title: "Theme & motion",
                                            value: ThemeStore.shared.theme.title)
                            }.buttonStyle(.plain)
                        }

                        GlassSection(title: "Chart Customization") {
                            NavigationLink { ChartCustomizationView() } label: {
                                GlassNavRow(icon: "chart.bar.xaxis", title: "Volume Profile & Heatmap",
                                            value: "Customize sensitivity")
                            }.buttonStyle(.plain)
                        }

                        GlassSection(title: "Configuration") {
                            NavigationLink { DerivConfigView() } label: {
                                GlassNavRow(icon: "antenna.radiowaves.left.and.right", title: "Deriv API & Token (PAT)",
                                            value: app.deriv.authorized ? "Connected" : (settings.useCustomDeriv ? "Custom" : "Public"))
                            }.buttonStyle(.plain)
                            Divider().overlay(Color.white.opacity(0.08))
                            NavigationLink { APIKeysView() } label: {
                                GlassNavRow(icon: "key.fill", title: "AI API Keys",
                                            value: "\(apiKeys.totalKeys) key\(apiKeys.totalKeys == 1 ? "" : "s")")
                            }.buttonStyle(.plain)
                            Divider().overlay(Color.white.opacity(0.08))
                            NavigationLink { ProviderValidationView() } label: {
                                GlassNavRow(icon: "checkmark.seal.fill", title: "Validate Providers",
                                            value: "Test NIM/Cerebras/FreeModel")
                            }.buttonStyle(.plain)
                            Divider().overlay(Color.white.opacity(0.08))
                            NavigationLink { LLMModelsView() } label: {
                                GlassNavRow(icon: "shippingbox.fill", title: "LLM Models",
                                            value: "\(app.models.models.count)")
                            }.buttonStyle(.plain)
                            Divider().overlay(Color.white.opacity(0.08))
                            NavigationLink { PipelinesView() } label: {
                                GlassNavRow(icon: "point.3.connected.trianglepath.dotted", title: "Pipelines",
                                            value: "\(app.pipelines.pipelines.count)")
                            }.buttonStyle(.plain)
                        }

                        GlassSection(title: "Notifications") {
                            GlassToggle(label: "Push alerts", desc: "Notify when a new signal fires", isOn: $settings.pushAlerts)
                        }

                        GlassSection(title: "Storage") {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(Glass.accent2).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("On My iPhone → EZIN").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                    Text("App auto-saves models, pipelines & data here").font(.caption2).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                            }.padding(.vertical, 6)
                        }

                        Text("EZIN v1.2.0 · Deriv perpetual scalper")
                            .font(.caption2).foregroundStyle(.white.opacity(0.3)).padding(.top, 4)
                    }
                    .padding(16).padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Provider Validation View

struct ProviderValidationView: View {
    @StateObject private var validator = ProviderValidator.shared
    @State private var showingResults = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                actionSection
                if validator.batchStatus.isValidating {
                    progressSection
                }
                if !validator.lastValidationResults.isEmpty {
                    resultsSection
                }
                infoSection
            }
            .padding()
        }
        .navigationTitle("Provider Validation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)

            Text("AI Provider Validation")
                .font(.title2)
                .fontWeight(.bold)

            Text("Test your Nvidia NIM, Cerebras, and FreeModel API keys for connectivity and compatibility")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var actionSection: some View {
        Button(action: {
            Task {
                await validator.validateAllProviders()
            }
        }) {
            HStack {
                if validator.batchStatus.isValidating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "play.fill")
                }
                Text(validator.batchStatus.isValidating ? "Validating..." : "Run Validation")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(validator.batchStatus.isValidating)
    }

    private var progressSection: some View {
        VStack(spacing: 12) {
            HStack {
                if let provider = validator.batchStatus.currentProvider {
                    Text("Testing: \(provider.rawValue)")
                        .font(.headline)
                }
                Spacer()
            }

            ProgressView(value: 0.5)
                .progressViewStyle(LinearProgressViewStyle())

            Text("Please wait while we test your API keys...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Validation Results")
                    .font(.headline)
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = validator.validationSummary()
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.accentColor)
                }
            }

            ForEach(validator.lastValidationResults) { result in
                ValidationResultRow(result: result)
            }

            HStack {
                let validCount = validator.lastValidationResults.filter { $0.isValid }.count
                let total = validator.lastValidationResults.count
                Text("\(validCount)/\(total) providers valid")
                    .font(.subheadline)
                    .foregroundColor(validCount == total ? .green : .orange)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Providers")
                .font(.headline)

            ProviderInfoRow(
                name: "Nvidia NIM",
                description: "High-performance inference with Llama 3.1 405B",
                features: ["Long context", "Code generation", "Analysis"]
            )

            ProviderInfoRow(
                name: "Cerebras",
                description: "Ultra-fast inference optimized for speed",
                features: ["Fast inference", "Cost effective", "Low latency"]
            )

            ProviderInfoRow(
                name: "FreeModel",
                description: "Free tier access with GPT-3.5 Turbo",
                features: ["Free tier", "Quick access", "Standard API"]
            )
        }
    }
}

struct ValidationResultRow: View {
    let result: ProviderValidationResult

    var body: some View {
        HStack {
            Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isValid ? .green : .red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.provider.rawValue)
                    .font(.headline)

                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let latency = result.latencyMs {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(latency)ms")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    if let model = result.modelUsed {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text(model)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ProviderInfoRow: View {
    let name: String
    let description: String
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    Text(feature)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
