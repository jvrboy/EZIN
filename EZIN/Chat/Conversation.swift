import Foundation

/// A saved chat conversation. Persisted so it survives tab switches and app restarts.
struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var createdAt = Date()
    var updatedAt = Date()
    var pinned = false
    var archived = false
    /// Optional project this conversation belongs to (shares the project's files + memory).
    var projectID: UUID? = nil

    /// Derive a short title from the first user message.
    static func autoTitle(from firstUserText: String) -> String {
        let t = firstUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "New chat" }
        let clipped = t.count > 40 ? String(t.prefix(40)) + "…" : t
        return clipped.replacingOccurrences(of: "\n", with: " ")
    }

    var lastActivity: Date { messages.last?.date ?? updatedAt }
    var preview: String {
        messages.last(where: { $0.role == "assistant" || $0.role == "user" })?.text
            .replacingOccurrences(of: "\n", with: " ") ?? "No messages yet"
    }
}

/// A project = a named folder on-device. Files added to a project are shared with
/// every conversation created inside it, and the project keeps its own memory notes.
struct ChatProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// File names stored under the project's folder (Projects/<id>/…).
    var files: [String] = []
    /// Free-form memory notes the assistant keeps for this project.
    var memory: [String] = []

    /// Folder name inside the app's Projects directory.
    var folderName: String { id.uuidString }
}

/// A single remembered fact (global memory the assistant carries across conversations).
struct MemoryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    /// Optional scope: nil = global, otherwise a conversation or project id.
    var scopeID: UUID? = nil
}
