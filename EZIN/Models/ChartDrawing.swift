import Foundation
import Combine

/// Serializable chart annotations. Stored locally so agents can add confluence levels
/// without cluttering the trade-signal surface.
struct ChartDrawing: Codable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case horizontalLine, verticalLine, rectangle, trendLine, ray }
    let id: UUID
    let kind: Kind
    let startIndex: Int
    let endIndex: Int
    let startPrice: Double
    let endPrice: Double
    let label: String
    let createdAt: Date

    init(kind: Kind, startIndex: Int, endIndex: Int, startPrice: Double, endPrice: Double, label: String = "") {
        self.id = UUID(); self.kind = kind; self.startIndex = startIndex; self.endIndex = endIndex
        self.startPrice = startPrice; self.endPrice = endPrice; self.label = label; self.createdAt = Date()
    }
}

@MainActor
final class ChartDrawingStore: ObservableObject {
    static let shared = ChartDrawingStore()
    @Published private(set) var drawings: [ChartDrawing] = [] { didSet { save() } }
    private let key = "chart.drawings.v1"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([ChartDrawing].self, from: data) else { return }
        drawings = saved
    }

    func add(_ drawing: ChartDrawing) { drawings.append(drawing) }
    func removeAll() { drawings.removeAll() }
    func remove(_ id: UUID) { drawings.removeAll { $0.id == id } }
    private func save() { if let data = try? JSONEncoder().encode(drawings) { UserDefaults.standard.set(data, forKey: key) } }
}
