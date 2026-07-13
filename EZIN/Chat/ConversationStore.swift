import Foundation
import Combine

/// Single source of truth for chat history. Persists conversations + projects to the
/// app directory so they survive tab switches AND app restarts (fixes the wipe bug).
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var projects: [ChatProject] = []
    @Published var currentID: UUID?

    private let convFile = "conversations.json"
    private let projFile = "projects.json"

    private init() {
        conversations = FileStore.shared.read([Conversation].self, from: convFile, in: FileStore.shared.chatDir) ?? []
        projects = FileStore.shared.read([ChatProject].self, from: projFile, in: FileStore.shared.chatDir) ?? []
        currentID = conversations.sorted { $0.lastActivity > $1.lastActivity }.first?.id
        if currentID == nil { _ = newConversation() }
    }

    // MARK: - Queries

    var current: Conversation? { conversations.first { $0.id == currentID } }

    var sorted: [Conversation] {
        conversations.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.lastActivity > $1.lastActivity
        }
    }

    var active: [Conversation] { sorted.filter { !$0.archived } }
    var archivedList: [Conversation] { sorted.filter { $0.archived } }

    func conversations(inProject id: UUID) -> [Conversation] {
        sorted.filter { $0.projectID == id }
    }

    // MARK: - Conversation lifecycle

    @discardableResult
    func newConversation(projectID: UUID? = nil, title: String = "New chat") -> Conversation {
        let c = Conversation(title: title, projectID: projectID)
        conversations.insert(c, at: 0)
        currentID = c.id
        save()
        return c
    }

    func select(_ id: UUID) { currentID = id }

    func appendToCurrent(_ message: ChatMessage) {
        guard let id = currentID, let i = conversations.firstIndex(where: { $0.id == id }) else {
            let c = newConversation()
            if let j = conversations.firstIndex(where: { $0.id == c.id }) {
                conversations[j].messages.append(message)
            }
            save(); return
        }
        conversations[i].messages.append(message)
        conversations[i].updatedAt = Date()
        // Auto-title from the first user message.
        if conversations[i].title == "New chat", message.role == "user" {
            conversations[i].title = Conversation.autoTitle(from: message.text)
        }
        save()
    }

    /// Replace the text of the last message with a given role (used for streaming/edits).
    func updateLastMessage(role: String, text: String) {
        guard let id = currentID, let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        if let j = conversations[i].messages.lastIndex(where: { $0.role == role }) {
            conversations[i].messages[j].text = text
            save()
        }
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? conversations[i].title : title
        save()
    }

    func togglePin(_ id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].pinned.toggle(); save()
    }

    func toggleArchive(_ id: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].archived.toggle(); save()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if currentID == id { currentID = active.first?.id ?? conversations.first?.id }
        if conversations.isEmpty { _ = newConversation() }
        save()
    }

    func assign(_ id: UUID, toProject projectID: UUID?) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].projectID = projectID; save()
    }

    // MARK: - Projects

    @discardableResult
    func addProject(name: String) -> ChatProject {
        let p = ChatProject(name: name.isEmpty ? "New project" : name)
        FileStore.shared.projectFolder(p)          // create the on-device folder
        projects.insert(p, at: 0)
        save()
        return p
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let i = projects.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        projects[i].name = name; save()
    }

    func deleteProject(_ id: UUID) {
        if let p = projects.first(where: { $0.id == id }) { FileStore.shared.deleteProjectFolder(p) }
        // Detach conversations from the deleted project (keep the chats).
        for i in conversations.indices where conversations[i].projectID == id { conversations[i].projectID = nil }
        projects.removeAll { $0.id == id }
        save()
    }

    func project(_ id: UUID?) -> ChatProject? { id.flatMap { pid in projects.first { $0.id == pid } } }

    /// Register a file (already written into the project folder) on the project.
    func addFile(_ fileName: String, toProject id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        if !projects[i].files.contains(fileName) { projects[i].files.append(fileName); save() }
    }

    func addProjectMemory(_ note: String, toProject id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].memory.append(note); save()
    }

    // MARK: - Persistence

    func save() {
        FileStore.shared.write(conversations, to: convFile, in: FileStore.shared.chatDir)
        FileStore.shared.write(projects, to: projFile, in: FileStore.shared.chatDir)
    }
}
