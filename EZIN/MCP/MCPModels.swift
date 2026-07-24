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
    var authHeader: String = ""        // optional "Authorization" value, e.g. "Bearer xyz"
    var enabled: Bool = true

    var headersDict: [String: String] {
        authHeader.isEmpty ? [:] : ["Authorization": authHeader]
    }
}

/// Persisted MCP connectors, pre-seeded with MT5 + TradingView presets the user can point at their own server.
final class MCPStore: ObservableObject {
    static let shared = MCPStore()
    @Published var connectors: [MCPConnector] { didSet { save() } }
    private let file = "mcp_connectors.json"

    private init() {
        let saved = FileStore.shared.read([MCPConnector].self, from: file, in: FileStore.shared.dataDir) ?? []
        connectors = MCPStore.merged(saved: saved)
    }

    func add(_ c: MCPConnector) { connectors.append(c) }
    func update(_ c: MCPConnector) { if let i = connectors.firstIndex(where: { $0.id == c.id }) { connectors[i] = c } }
    func remove(_ c: MCPConnector) { connectors.removeAll { $0.id == c.id } }

    /// Resolve a connector by user-typed server name or kind.
    func byServerName(_ name: String) -> MCPConnector? {
        let n = name.lowercased()
        return connectors.first { $0.enabled && ($0.name.lowercased() == n || $0.kind.rawValue == n || $0.kind.title.lowercased() == n) }
    }

    private func save() { FileStore.shared.write(connectors, to: file, in: FileStore.shared.dataDir) }

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
