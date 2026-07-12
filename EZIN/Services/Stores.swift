import Foundation
import Combine

/// General app settings persisted to UserDefaults.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let d = UserDefaults.standard
    private init() {}

    @Published var derivAppID: Int = {
        let v = UserDefaults.standard.integer(forKey: "derivAppID")
        return v == 0 ? DerivClient.defaultAppID : v
    }() { didSet { d.set(derivAppID, forKey: "derivAppID") } }

    @Published var useCustomDeriv: Bool = UserDefaults.standard.bool(forKey: "useCustomDeriv") {
        didSet { d.set(useCustomDeriv, forKey: "useCustomDeriv") }
    }

    @Published var pushAlerts: Bool = UserDefaults.standard.object(forKey: "pushAlerts") as? Bool ?? true {
        didSet { d.set(pushAlerts, forKey: "pushAlerts") }
    }
    @Published var autoTrade: Bool = UserDefaults.standard.bool(forKey: "autoTrade") {
        didSet { d.set(autoTrade, forKey: "autoTrade") }
    }
    @Published var riskPerTrade: Double = UserDefaults.standard.object(forKey: "riskPerTrade") as? Double ?? 2.0 {
        didSet { d.set(riskPerTrade, forKey: "riskPerTrade") }
    }
    @Published var defaultStrategy: String = UserDefaults.standard.string(forKey: "defaultStrategy") ?? "Council Consensus" {
        didSet { d.set(defaultStrategy, forKey: "defaultStrategy") }
    }

    var watchlist: [String] {
        get { (d.array(forKey: "watchlist") as? [String]) ?? Array(DerivSymbols.all.prefix(6)) }
        set { d.set(newValue, forKey: "watchlist") }
    }
}

/// Imported LLM models registry (persisted as JSON in the app directory).
final class LLMModelStore: ObservableObject {
    static let shared = LLMModelStore()
    @Published var models: [LLMModel] = []
    private let file = "models.json"

    private init() { load() }

    func load() {
        models = FileStore.shared.read([LLMModel].self, from: file, in: FileStore.shared.dataDir) ?? []
    }
    func add(_ model: LLMModel) { models.insert(model, at: 0); save() }
    func remove(_ model: LLMModel) {
        FileStore.shared.deleteModel(model)
        models.removeAll { $0.id == model.id }; save()
    }
    private func save() { FileStore.shared.write(models, to: file, in: FileStore.shared.dataDir) }
}

/// Pipeline registry.
final class PipelineStore: ObservableObject {
    static let shared = PipelineStore()
    @Published var pipelines: [Pipeline] = []
    private let file = "pipelines.json"

    private init() {
        pipelines = FileStore.shared.read([Pipeline].self, from: file, in: FileStore.shared.pipelinesDir) ?? [.default]
    }
    func add(_ p: Pipeline) { pipelines.append(p); save() }
    func update(_ p: Pipeline) {
        if let i = pipelines.firstIndex(where: { $0.id == p.id }) { pipelines[i] = p; save() }
    }
    func remove(_ p: Pipeline) { pipelines.removeAll { $0.id == p.id }; save() }
    func save() { FileStore.shared.write(pipelines, to: file, in: FileStore.shared.pipelinesDir) }
}

/// Signal history registry.
final class HistoryStore {
    static let shared = HistoryStore()
    private let file = "history.json"
    func load() -> [SignalOutcome] {
        FileStore.shared.read([SignalOutcome].self, from: file, in: FileStore.shared.dataDir) ?? Self.seed
    }
    func save(_ items: [SignalOutcome]) {
        FileStore.shared.write(items, to: file, in: FileStore.shared.dataDir)
    }
    static let seed: [SignalOutcome] = [
        .init(displayPair: "EUR/USD", type: .buy, win: true, pips: 42, closedAt: Date().addingTimeInterval(-86400)),
        .init(displayPair: "XAU/USD", type: .sell, win: true, pips: 128, closedAt: Date().addingTimeInterval(-90000)),
        .init(displayPair: "GBP/USD", type: .buy, win: false, pips: -18, closedAt: Date().addingTimeInterval(-172800)),
        .init(displayPair: "V75", type: .sell, win: true, pips: 210, closedAt: Date().addingTimeInterval(-176400)),
        .init(displayPair: "BTC/USD", type: .buy, win: false, pips: -35, closedAt: Date().addingTimeInterval(-259200)),
        .init(displayPair: "USD/JPY", type: .sell, win: true, pips: 27, closedAt: Date().addingTimeInterval(-262800)),
    ]
}
