import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        GlassSection(title: "Trading Bot") {
                            NavigationLink { BotSettingsView() } label: {
                                GlassNavRow(icon: "cpu", title: "Bot configuration",
                                            value: "\(app.botConfig.config.instruments.count) instruments")
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
                                            value: "\(app.credentials.configured.filter { $0.isAIProvider }.count)")
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

                        Text("EZIN v1.1.0 · Deriv perpetual scalper")
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
