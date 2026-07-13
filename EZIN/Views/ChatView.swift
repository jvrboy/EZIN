import SwiftUI

/// Chat tab — persistent, project-aware conversation surface. The backend runs a
/// multi-agent orchestrator with tool + MCP execution; the surface stays clean.
/// Conversations, projects and memory all persist across tab switches and restarts.
struct ChatView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var vm = ChatViewModel()
    @ObservedObject private var store = ConversationStore.shared

    @State private var showHistory = false
    @State private var showProjects = false

    private var messages: [ChatMessage] { store.current?.messages ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty { intro }
                        ForEach(messages) { m in ChatBubble(message: m).id(m.id) }
                        if vm.busy {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Thinking…").font(.caption).foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    // Scroll ONLY when the user just sent a message — never on assistant
                    // output, and never animated. Reading position stays put otherwise.
                    .onChange(of: vm.pendingScrollID) { id in
                        guard let id = id else { return }
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            inputBar
        }
        .sheet(isPresented: $showHistory) { ConversationsListView() }
        .sheet(isPresented: $showProjects) { ProjectsView() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }.buttonStyle(.plain)

            VStack(spacing: 1) {
                Text(store.current?.title ?? "EZIN Assistant")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let pid = store.current?.projectID, let p = store.project(pid) {
                    Text("Project · \(p.name)").font(.system(size: 10)).foregroundStyle(Glass.accent2)
                }
            }
            .frame(maxWidth: .infinity)

            Button { showProjects = true } label: {
                Image(systemName: "folder").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }.buttonStyle(.plain)

            Button { store.newConversation(projectID: store.current?.projectID) } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Glass.accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EZIN Assistant").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("Ask me to analyze any instrument, explain signals, manage trades, generate files, or anything else. Backed by \(AgentRegistry.agents.count) agents, \(AgentRegistry.pipelines.count) pipelines, your AI keys and MCP tools. Conversations, projects and memory are saved automatically.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["Analyze Volatility 75 on 5m", "What are my top live signals?", "Explain the Ichimoku cloud", "Create a WAV tone artifact"], id: \.self) { s in
                    Button { vm.input = s } label: {
                        Text(s).font(.system(size: 13)).foregroundStyle(Glass.accent2)
                            .padding(.horizontal, 12).padding(.vertical, 8).glassCard(corner: 12)
                    }.buttonStyle(.plain)
                }
            }
            if AIRouter.availableProviders().isEmpty {
                Text("Tip: add an AI API key in Settings → AI API Keys to enable the assistant.")
                    .font(.caption2).foregroundStyle(Glass.sell.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message EZIN…", text: $vm.input)
                .foregroundStyle(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .onSubmit { vm.send(app: app) }
            Button { vm.send(app: app) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    .foregroundStyle(vm.input.isEmpty ? .white.opacity(0.3) : Glass.accent)
            }
            .buttonStyle(.plain)
            .disabled(vm.input.isEmpty || vm.busy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        if message.role == "tool" {
            Text(message.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == "assistant" {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    MarkdownView(text: message.text)
                    if let name = message.artifactName, let path = message.artifactPath {
                        ArtifactChip(name: name, relativePath: path)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                Spacer(minLength: 24)
            }
        } else {
            HStack {
                Spacer(minLength: 36)
                Text(message.text)
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Glass.accent.opacity(0.35)))
            }
        }
    }
}

/// Orchestrates the conversation: persists to ConversationStore, auto-routes the AI,
/// runs tool actions, captures memory, loops.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input = ""
    @Published var busy = false
    @Published var pendingScrollID: UUID?

    private let store = ConversationStore.shared
    private let memory = MemoryStore.shared

    func send(app: AppState) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        if let fact = MemoryStore.extractRememberRequest(text) { memory.remember(fact, scope: store.currentID) }
        let userMsg = ChatMessage(role: "user", text: text)
        store.appendToCurrent(userMsg)
        pendingScrollID = userMsg.id
        busy = true
        Task { await runLoop(app: app) }
    }

    private func runLoop(app: AppState) async {
        let cfg = ChatConfigStore.shared.config
        var system = cfg.systemPrompt + "\n\n" + AgentRegistry.systemContext()
        system += memory.contextBlock(scope: store.currentID)
        if let pid = store.current?.projectID, let proj = store.project(pid) { system += projectContext(proj) }

        let tools = ToolRegistry(app: app)
        var turns: [ChatTurn] = (store.current?.messages ?? []).filter { $0.role != "tool" }.map {
            ($0.role == "assistant" ? "assistant" : "user", $0.text)
        }

        var steps = 0
        while steps < 5 {
            steps += 1
            let result = await AIRouter.complete(system: system, messages: turns)
            switch result {
            case .failure(let e):
                store.appendToCurrent(ChatMessage(role: "assistant", text: "⚠️ \(e.localizedDescription)"))
                busy = false; return
            case .success(let reply):
                if let action = parseAction(reply) {
                    store.appendToCurrent(ChatMessage(role: "tool", text: "⚙️ \(action.tool)(\(compact(action.args)))"))
                    let out = await tools.run(action.tool, args: action.args)
                    // If a tool produced an artifact, attach it to a dedicated bubble.
                    if let art = ArtifactStore.shared.lastArtifact, action.tool.hasPrefix("create_") {
                        var m = ChatMessage(role: "assistant", text: "Created **\(art.name)** — tap to download or share.")
                        m.artifactPath = art.relativePath; m.artifactName = art.name
                        store.appendToCurrent(m)
                        ArtifactStore.shared.lastArtifact = nil
                        busy = false; return
                    }
                    turns.append(("assistant", reply))
                    turns.append(("user", "TOOL_RESULT \(action.tool): \(out)"))
                } else {
                    store.appendToCurrent(ChatMessage(role: "assistant", text: reply))
                    busy = false; return
                }
            }
        }
        busy = false
    }

    private func projectContext(_ p: ChatProject) -> String {
        var s = "\n\nPROJECT: \(p.name). Shared files: "
        s += p.files.isEmpty ? "(none yet)." : p.files.joined(separator: ", ") + "."
        if !p.memory.isEmpty { s += " Project notes: " + p.memory.joined(separator: "; ") + "." }
        return s
    }

    private func parseAction(_ reply: String) -> (tool: String, args: [String: Any])? {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ACTION:") else { return nil }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else { return nil }
        let sub = String(trimmed[start...end])
        guard let data = sub.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = obj["tool"] as? String else { return nil }
        return (tool, (obj["args"] as? [String: Any]) ?? [:])
    }

    private func compact(_ args: [String: Any]) -> String {
        args.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }
}
