import Foundation

struct Skill: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var format: String          // md | skill | json | txt
    var summary: String
    var content: String
    var tools: [String] = []
    var executionScripts: [String] = []
    var createdAt = Date()
}

/// User-extensible capability packs for the chat assistant. Skills are stored locally and
/// injected into the tool prompt through skills_list/skill_create/skill_import.
@MainActor
final class SkillStore: ObservableObject {
    static let shared = SkillStore()
    @Published private(set) var skills: [Skill] = []
    private let file = "skills.json"

    private init() { load() }

    func load() {
        skills = FileStore.shared.read([Skill].self, from: file, in: FileStore.shared.chatDir) ?? []
        if skills.isEmpty { installStarterSkills() }
    }

    func save() { FileStore.shared.write(skills, to: file, in: FileStore.shared.chatDir) }

    @discardableResult
    func create(name: String, format: String = "md", summary: String, content: String, tools: [String] = [], executionScripts: [String] = []) -> Skill {
        let skill = Skill(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                          format: format.lowercased(),
                          summary: summary,
                          content: content,
                          tools: tools,
                          executionScripts: executionScripts)
        skills.removeAll { $0.name.caseInsensitiveCompare(skill.name) == .orderedSame }
        skills.insert(skill, at: 0)
        save()
        return skill
    }

    @discardableResult
    func importText(_ text: String, suggestedName: String = "Imported Skill") -> Skill {
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let name = (obj["name"] as? String) ?? suggestedName
            let summary = (obj["summary"] as? String) ?? (obj["description"] as? String) ?? "Imported JSON skill"
            let content = (obj["content"] as? String) ?? text
            let tools = (obj["tools"] as? [String]) ?? []
            let scripts = (obj["execution_scripts"] as? [String]) ?? (obj["scripts"] as? [String]) ?? []
            return create(name: name, format: "json", summary: summary, content: content, tools: tools, executionScripts: scripts)
        }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? suggestedName
        let name = firstLine.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        return create(name: name.isEmpty ? suggestedName : name, format: "md", summary: "Imported Markdown skill", content: text)
    }

    func remove(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
        save()
    }

    func promptSummary(limit: Int = 12) -> String {
        guard !skills.isEmpty else { return "No custom skills installed." }
        return skills.prefix(limit).map { "- \($0.name) [\($0.format)]: \($0.summary)" }.joined(separator: "\n")
    }

    private func installStarterSkills() {
        skills = [
            Skill(name: "File Creator", format: "md", summary: "Create HTML, Markdown, JSON, CSV, code and document files without MCP.", content: "Use create_file/create_artifact with a complete file body. Register the artifact so the user can open or share it.", tools: ["create_file", "create_artifact", "read_file", "rename_file"], executionScripts: []),
            Skill(name: "PDF Summarizer", format: "md", summary: "Extract PDF text with PDFKit and produce grounded summaries.", content: "For any uploaded statement/report PDF, call summarize_file(name|path). If text is empty, say OCR is required; never invent figures.", tools: ["summarize_file", "read_file", "list_files"], executionScripts: []),
            Skill(name: "Full Backend Confluence", format: "json", summary: "Run systematic, mathematical, RNG, neural, chaos, Bayesian, fuzzy, order-flow, session, anomaly and risk engines as one signal pipeline.", content: "Call full_backend_report for the broadest audit, then explain which engines agreed or disagreed.", tools: ["full_backend_report", "ultra_confirm", "correlation_matrix", "deep_risk"], executionScripts: []),
            Skill(name: "Recovery Bin", format: "md", summary: "Deleted/archived chats and projects go to a recoverable bin before permanent removal.", content: "Use the History → Bin view to restore or permanently delete items.", tools: ["list_files", "delete_file"], executionScripts: [])
        ]
        save()
    }
}
