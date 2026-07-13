import SwiftUI

/// Chat tab — a clean chat interface. The backend runs a multi-agent orchestrator with
/// tool + MCP execution, but the surface stays a simple conversation.
struct ChatView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var vm = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if vm.messages.isEmpty { intro }
                        ForEach(vm.messages) { m in ChatBubble(message: m).id(m.id) }
                        if vm.busy {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Thinking…").font(.caption).foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .onChange(of: vm.messages.count) { _ in
                        // Only jump to the bottom when the user just sent a message.
                        // Never auto-scroll on assistant/tool output (and never animate),
                        // so the reading position stays put while replies stream in.
                        guard vm.messages.last?.role == "user", let last = vm.messages.last else { return }
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            inputBar
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EZIN Assistant").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("Ask me to analyze any instrument, explain signals, manage trades, or anything else. Backed by \(AgentRegistry.agents.count) agents, \(AgentRegistry.pipelines.count) pipelines, your AI keys and MCP tools.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["Analyze Volatility 75 on 5m", "What are my top live signals?", "Explain the Ichimoku cloud"], id: \.self) { s in
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
        } else {
            HStack {
                if message.role == "assistant" { bubble; Spacer(minLength: 36) }
                else { Spacer(minLength: 36); bubble }
            }
        }
    }
    private var bubble: some View {
        Group {
            if message.role == "assistant" {
                MarkdownText(markdown: message.text)   // professional headings/lists/bold
            } else {
                Text(message.text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.95))
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(message.role == "assistant" ? Color.white.opacity(0.08) : Glass.accent.opacity(0.35))
        )
    }
}

/// Orchestrates the conversation: calls the auto-routed AI, runs tool actions, loops.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var busy = false

    func send(app: AppState) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        messages.append(ChatMessage(role: "user", text: text))
        busy = true
        Task { await runLoop(app: app) }
    }

    private func runLoop(app: AppState) async {
        let cfg = ChatConfigStore.shared.config
        let system = cfg.systemPrompt + "\n\n" + AgentRegistry.systemContext()
        let tools = ToolRegistry(app: app)
        var turns: [ChatTurn] = messages.filter { $0.role != "tool" }.map {
            ($0.role == "assistant" ? "assistant" : "user", $0.text)
        }

        var steps = 0
        while steps < 5 {
            steps += 1
            let result = await AIRouter.complete(system: system, messages: turns)
            switch result {
            case .failure(let e):
                messages.append(ChatMessage(role: "assistant", text: "⚠️ \(e.localizedDescription)"))
                busy = false; return
            case .success(let reply):
                if let action = parseAction(reply) {
                    messages.append(ChatMessage(role: "tool", text: "⚙️ \(action.tool)(\(compact(action.args)))"))
                    let out = await tools.run(action.tool, args: action.args)
                    turns.append(("assistant", reply))
                    turns.append(("user", "TOOL_RESULT \(action.tool): \(out)"))
                } else {
                    messages.append(ChatMessage(role: "assistant", text: reply))
                    busy = false; return
                }
            }
        }
        busy = false
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
