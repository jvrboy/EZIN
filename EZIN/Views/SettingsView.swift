import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settings = SettingsStore.shared

    private let strategies = ["Council Consensus", "714 Method", "ICT / SMC", "SMT Divergence", "Price Action", "Time & Price"]

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {

                        GlassSection(title: "Configuration") {
                            NavigationLink { DerivConfigView() } label: {
                                GlassNavRow(icon: "antenna.radiowaves.left.and.right", title: "Deriv API",
                                            value: settings.useCustomDeriv ? "Custom" : "Public")
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

                        GlassSection(title: "Notifications & Trading") {
                            GlassToggle(label: "Push alerts", desc: "Notify when a new signal fires", isOn: $settings.pushAlerts)
                            Divider().overlay(Color.white.opacity(0.08))
                            GlassToggle(label: "Auto-trade", desc: "Execute signals automatically (use with caution)", isOn: $settings.autoTrade)
                        }

                        GlassSection(title: "Risk per trade") {
                            VStack(alignment: .leading, spacing: 8) {
                                Slider(value: $settings.riskPerTrade, in: 0.5...10, step: 0.5).tint(Glass.accent)
                                Text("\(settings.riskPerTrade, specifier: "%.1f")% of account balance")
                                    .font(.caption).foregroundStyle(.white.opacity(0.45))
                            }
                        }

                        GlassSection(title: "Default strategy") {
                            FlowChips(items: strategies, selection: $settings.defaultStrategy)
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

                        Text("EZIN v1.0.0 · Deriv signal intelligence")
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

struct FlowChips: View {
    let items: [String]
    @Binding var selection: String
    var body: some View {
        FlexibleWrap(items) { item in
            Button { selection = item } label: {
                Text(item)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background((selection == item ? Glass.accent : Color.white).opacity(selection == item ? 0.25 : 0.05))
                    .foregroundStyle(selection == item ? Color.white : .white.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(selection == item ? 0.4 : 0.12), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }
}

/// Simple wrapping layout for chips (iOS 15 compatible).
struct FlexibleWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items; self.content = content
    }
    var body: some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(items, id: \.self) { item in
                    content(item)
                        .padding(4)
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width { width = 0; height -= d.height }
                            let result = width
                            if item == items.last { width = 0 } else { width -= d.width }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == items.last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(height: 120)
    }
}
