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

    /// Agent names disabled by the user in Chat → Specialist Agents.
    var disabledAgentNames: [String] {
        get { d.array(forKey: "disabledAgentNames") as? [String] ?? [] }
        set { d.set(newValue, forKey: "disabledAgentNames") }
    }

    /// Symbols scanned for the Signals tab when the bot is not actively trading.
    var watchlist: [String] {
        get {
            if let saved = d.array(forKey: "watchlist") as? [String] { return saved }
            // Built stepwise: the single chained expression blew the type-checker's budget.
            var list: [String] = []
            list.append(contentsOf: DerivSymbols.volatility.prefix(3))
            list.append(contentsOf: DerivSymbols.boom.prefix(1))
            list.append(contentsOf: DerivSymbols.crash.prefix(1))
            list.append(contentsOf: DerivSymbols.jump.prefix(1))
            list.append(contentsOf: DerivSymbols.forex.prefix(4))
            list.append(contentsOf: DerivSymbols.commodity.prefix(2))
            list.append(contentsOf: DerivSymbols.crypto.prefix(4))
            list.append(contentsOf: DerivSymbols.stockIndex.prefix(3))
            return list
        }
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
