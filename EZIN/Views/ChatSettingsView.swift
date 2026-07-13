import SwiftUI

/// Customize the Chat tab: routing, trading permission, creativity, system prompt, and MCP.
struct ChatSettingsView: View {
    @ObservedObject private var store = ChatConfigStore.shared
    @ObservedObject private var mcp = MCPStore.shared

    var body: some View {
        GlassScreen(title: "Chat & Agents") {
            GlassSection(title: "Routing") {
                GlassToggle(label: "Auto-route AI", desc: "Automatically use the most powerful available model, with fallback", isOn: $store.config.autoRoute)
                Divider().overlay(Color.white.opacity(0.08))
                GlassToggle(label: "Allow trading from chat", desc: "Let the assistant place real Deriv trades when asked", isOn: $store.config.allowTrading)
            }

            GlassSection(title: "Creativity") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temperature \(String(format: "%.1f", store.config.temperature))")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    Slider(value: $store.config.temperature, in: 0...1).tint(Glass.accent)
                }.padding(.vertical, 4)
            }

            GlassSection(title: "System Prompt") {
                TextEditor(text: $store.config.systemPrompt)
                    .frame(minHeight: 150)
                    .foregroundStyle(.white)
                    .scrollContentBackgroundHiddenCompat()
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                Button("Reset to default") { store.config.systemPrompt = ChatConfig.defaultPrompt }
                    .font(.caption).foregroundStyle(Glass.accent2)
            }

            GlassSection(title: "Backend") {
                GlassNavRow(icon: "person.3.fill", title: "Specialist agents", value: "\(AgentRegistry.agents.count)")
                Divider().overlay(Color.white.opacity(0.08))
                GlassNavRow(icon: "point.3.connected.trianglepath.dotted", title: "Pipelines", value: "\(AgentRegistry.pipelines.count)")
                Divider().overlay(Color.white.opacity(0.08))
                NavigationLink { MCPConnectorsView() } label: {
                    GlassNavRow(icon: "puzzlepiece.extension.fill", title: "MCP Connectors", value: "\(mcp.connectors.count)")
                }.buttonStyle(.plain)
            }
        }
    }
}

extension View {
    /// Hide the TextEditor background on iOS 16+, no-op on iOS 15.
    @ViewBuilder func scrollContentBackgroundHiddenCompat() -> some View {
        if #available(iOS 16.0, *) { self.scrollContentBackground(.hidden) } else { self }
    }
}
