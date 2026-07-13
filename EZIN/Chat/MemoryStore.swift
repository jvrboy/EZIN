import Foundation
import Combine

/// Long-term memory: facts the assistant should remember across ALL conversations
/// (preferences, account style, recurring instruments, etc.). Persisted on-device.
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()
    @Published private(set) var items: [MemoryItem] = []
    private let file = "memory.json"
    private let maxItems = 200

    private init() {
        items = FileStore.shared.read([MemoryItem].self, from: file, in: FileStore.shared.chatDir) ?? []
    }

    func remember(_ text: String, scope: UUID? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // De-dupe near-identical facts.
        guard !items.contains(where: { $0.text.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        items.insert(MemoryItem(text: t, scopeID: scope), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
    }

    func forget(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    func clear() { items = []; save() }

    /// Facts relevant to a given scope (global + that scope).
    func relevant(scope: UUID?) -> [MemoryItem] {
        items.filter { $0.scopeID == nil || $0.scopeID == scope }
    }

    /// Compact block injected into the system prompt so the model "remembers".
    func contextBlock(scope: UUID?) -> String {
        let relevant = relevant(scope: scope).prefix(30)
        guard !relevant.isEmpty else { return "" }
        return "\n\nMEMORY (things to remember about this user):\n" +
            relevant.map { "- \($0.text)" }.joined(separator: "\n")
    }

    /// Extract "remember that …" style instructions from a user message.
    /// Returns the extracted fact if the user asked to be remembered, else nil.
    static func extractRememberRequest(_ text: String) -> String? {
        let lower = text.lowercased()
        let triggers = ["remember that ", "remember this: ", "remember: ", "note that ", "keep in mind that ", "don't forget that "]
        for t in triggers where lower.contains(t) {
            if let range = lower.range(of: t) {
                let fact = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !fact.isEmpty { return fact }
            }
        }
        return nil
    }

    func save() { FileStore.shared.write(items, to: file, in: FileStore.shared.chatDir) }
}
