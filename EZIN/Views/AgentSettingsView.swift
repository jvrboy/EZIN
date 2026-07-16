import SwiftUI

/// Live specialist-agent control panel. Toggling a runtime agent immediately changes the
/// signal council; registry agents document the hidden backend tools available to chat.
struct AgentSettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settings = SettingsStore.shared

    private var disabled: Set<String> { Set(settings.disabledAgentNames) }

    var body: some View {
        GlassScreen(title: "Specialist Agents") {
            GlassSection(title: "Runtime council") {
                ForEach(app.engine.agents.indices, id: \.self) { i in
                    let agent = app.engine.agents[i]
                    Toggle(isOn: binding(for: agent.name)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                            Text(agent.role).font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .tint(Glass.accent)
                }
            }

            GlassSection(title: "Backend tool agents") {
                ForEach(AgentRegistry.agents) { agent in
                    HStack(spacing: 10) {
                        Image(systemName: "cpu").foregroundStyle(Glass.accent2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                            Text(agent.role).font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { !disabled.contains(name) },
            set: { enabled in
                var names = Set(settings.disabledAgentNames)
                if enabled { names.remove(name) } else { names.insert(name) }
                settings.disabledAgentNames = Array(names).sorted()
                for i in app.engine.agents.indices where app.engine.agents[i].name == name {
                    app.engine.agents[i].isActive = enabled
                }
            }
        )
    }
}
