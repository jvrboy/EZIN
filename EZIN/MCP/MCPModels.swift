import Foundation
import Combine

enum MCPKind: String, Codable, CaseIterable, Identifiable {
    case mt5, tradingview, binance, oanda, interactiveBrokers, alpaca, polygon, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mt5: return "MetaTrader 5"
        case .tradingview: return "TradingView"
        case .binance: return "Binance"
        case .oanda: return "OANDA"
        case .interactiveBrokers: return "Interactive Brokers"
        case .alpaca: return "Alpaca"
        case .polygon: return "Polygon.io"
        case .custom: return "Custom MCP"
        }
    }
    var icon: String {
        switch self {
        case .mt5: return "chart.bar.doc.horizontal"
        case .tradingview: return "chart.xyaxis.line"
        case .binance: return "b.circle"
        case .oanda: return "dollarsign.arrow.circlepath"
        case .interactiveBrokers: return "building.columns"
        case .alpaca: return "leaf"
        case .polygon: return "hexagon"
        case .custom: return "puzzlepiece.extension"
        }
    }
}

/// A user-configured MCP server connection.
struct MCPConnector: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: MCPKind
    var url: String
    /// Kept in memory for the editor only. MCPStore persists it in the device-only
    /// Keychain rather than in the Documents JSON file exposed through Files.
    var authHeader: String = ""
    var enabled: Bool = true

    var secretAccount: String { "mcp.auth.\(id.uuidString)" }

    var headersDict: [String: String] {
        let value = authHeader.isEmpty
            ? CredentialStore.shared.secret(account: secretAccount) ?? ""
            : authHeader
        return value.isEmpty ? [:] : ["Authorization": value]
    }
}

/// Persisted MCP connectors, pre-seeded with MT5 + TradingView presets the user can point at their own server.
final class MCPStore: ObservableObject {
    static let shared = MCPStore()
    @Published var connectors: [MCPConnector] { didSet { save() } }
    private let file = "mcp_connectors.json"

    private init() {
        let saved = FileStore.shared.read([MCPConnector].self, from: file, in: FileStore.shared.dataDir) ?? []
        // Migrate legacy plaintext auth headers exactly once.
        for connector in saved where !connector.authHeader.isEmpty {
            CredentialStore.shared.setSecret(connector.authHeader, account: connector.secretAccount)
        }
        connectors = MCPStore.merged(saved: saved).map { connector in
            var sanitized = connector
            sanitized.authHeader = ""
            return sanitized
        }
        save()
    }

    func add(_ c: MCPConnector) {
        persistSecret(c)
        var sanitized = c; sanitized.authHeader = ""
        connectors.append(sanitized)
    }

    func update(_ c: MCPConnector) {
        persistSecret(c)
        var sanitized = c; sanitized.authHeader = ""
        if let i = connectors.firstIndex(where: { $0.id == c.id }) { connectors[i] = sanitized }
    }

    func clearSecret(for c: MCPConnector) {
        CredentialStore.shared.removeSecret(account: c.secretAccount)
        if let index = connectors.firstIndex(where: { $0.id == c.id }) {
            connectors[index].authHeader = ""
        }
    }

    func remove(_ c: MCPConnector) {
        CredentialStore.shared.removeSecret(account: c.secretAccount)
        connectors.removeAll { $0.id == c.id }
    }

    /// Resolve a connector by user-typed server name or kind.
    func byServerName(_ name: String) -> MCPConnector? {
        let n = name.lowercased()
        return connectors.first { $0.enabled && ($0.name.lowercased() == n || $0.kind.rawValue == n || $0.kind.title.lowercased() == n) }
    }

    private func persistSecret(_ connector: MCPConnector) {
        // An empty editor value means “leave the existing Keychain secret alone”.
        // The remove action is the only operation that deletes credentials.
        if !connector.authHeader.isEmpty {
            CredentialStore.shared.setSecret(connector.authHeader, account: connector.secretAccount)
        }
    }

    private func save() {
        // Never serialize authHeader to the app's user-visible Documents directory.
        let sanitized = connectors.map { connector -> MCPConnector in
            persistSecret(connector)
            var copy = connector
            copy.authHeader = ""
            return copy
        }
        FileStore.shared.write(sanitized, to: file, in: FileStore.shared.dataDir)
    }

    private static func merged(saved: [MCPConnector]) -> [MCPConnector] {
        var merged = saved.isEmpty ? presets : saved
        for preset in presets where !merged.contains(where: { $0.kind == preset.kind || $0.name.lowercased() == preset.name.lowercased() }) {
            merged.append(preset)
        }
        return merged
    }

    /// Presets based on popular open-source MCP servers (disabled until the user sets their own URL).
    /// MT5 e.g. vincentwongso/mt5-trading-mcp or amirkhonov/metatrader5-mcp (run locally / Docker).
    /// TradingView e.g. atilaahmettaner/tradingview-mcp.
    static let presets: [MCPConnector] = [
        MCPConnector(name: "MetaTrader 5", kind: .mt5, url: "http://localhost:8000/mcp", authHeader: "", enabled: false),
        MCPConnector(name: "TradingView", kind: .tradingview, url: "http://localhost:8001/mcp", authHeader: "", enabled: false),
        MCPConnector(name: "Binance", kind: .binance, url: "http://localhost:8002/mcp", authHeader: "", enabled: false),
        MCPConnector(name: "OANDA", kind: .oanda, url: "http://localhost:8003/mcp", authHeader: "", enabled: false),
        MCPConnector(name: "Interactive Brokers", kind: .interactiveBrokers, url: "http://localhost:8004/mcp", authHeader: "", enabled: false),
        MCPConnector(name: "Alpaca", kind: .alpaca, url: "http://localhost:8005/mcp", authHeader: "", enabled: false),
        MCPConnector(name: "Polygon.io", kind: .polygon, url: "http://localhost:8006/mcp", authHeader: "", enabled: false)
    ]
}
