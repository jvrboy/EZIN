import SwiftUI

/// Configure MCP server connections (MT5, TradingView, or any custom MCP).
struct MCPConnectorsView: View {
    @ObservedObject private var store = MCPStore.shared
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        GlassScreen(title: "MCP Connectors") {
            ForEach($store.connectors) { $c in
                GlassSection(title: c.kind.title) {
                    GlassToggle(label: "Enabled", isOn: $c.enabled)
                    Divider().overlay(Color.white.opacity(0.08))
                    GlassField(placeholder: "Server URL (https://…/mcp)", text: $c.url)
                    GlassField(placeholder: "Authorization header (optional)", text: $c.authHeader, secure: true)
                    HStack {
                        Button { test(c) } label: {
                            Text("Test connection").font(.system(size: 13, weight: .medium)).foregroundStyle(Glass.accent2)
                        }.buttonStyle(.plain)
                        Spacer()
                        if c.kind == .custom {
                            Button { store.remove(c) } label: {
                                Image(systemName: "trash").foregroundStyle(Glass.sell)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 4)
                }
            }

            Button {
                store.add(MCPConnector(name: "Custom \(store.connectors.count + 1)", kind: .custom, url: ""))
            } label: {
                HStack { Image(systemName: "plus.circle.fill"); Text("Add custom MCP server") }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Glass.accent)
            }.buttonStyle(.plain)

            if testing { ProgressView().tint(.white) }
            if let r = testResult {
                Text(r).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard(corner: 12)
            }

            Text("Run an MCP server and point the URL here. MT5: e.g. vincentwongso/mt5-trading-mcp or amirkhonov/metatrader5-mcp (Windows/Docker). TradingView: e.g. atilaahmettaner/tradingview-mcp. Then the Chat assistant can call their tools via mcp(server, tool, args).")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
    }

    private func test(_ c: MCPConnector) {
        testing = true; testResult = nil
        Task {
            do {
                let tools = try await MCPClient(connector: c).listTools()
                testResult = "\(c.name): \(tools.count) tools — \(tools.prefix(10).joined(separator: ", "))"
            } catch {
                testResult = "\(c.name): \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
