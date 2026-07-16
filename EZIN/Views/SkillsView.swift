import SwiftUI

/// Manage local assistant skills: MD / SKILL / JSON and other UTF-8 text formats.
struct SkillsView: View {
    @ObservedObject private var store = SkillStore.shared
    @State private var showCreate = false
    @State private var showImport = false

    var body: some View {
        GlassScreen(title: "Skills") {
            GlassSection(title: "Installed") {
                if store.skills.isEmpty {
                    Text("No skills installed.").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                ForEach(store.skills) { skill in
                    NavigationLink { SkillDetailView(skill: skill) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "brain.head.profile").foregroundStyle(Glass.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                                Text("\(skill.format.uppercased()) · \(skill.summary)").font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button(role: .destructive) { store.remove(skill) } label: { Label("Delete", systemImage: "trash") } }
                }
            }

            GlassSection(title: "Add") {
                Button { showCreate = true } label: { GlassNavRow(icon: "plus.square", title: "Create skill", value: "MD/JSON") }.buttonStyle(.plain)
                Divider().overlay(Color.white.opacity(0.08))
                Button { showImport = true } label: { GlassNavRow(icon: "square.and.arrow.down", title: "Import skill file", value: "MD · SKILL · JSON") }.buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showCreate) { SkillEditorView() }
        .sheet(isPresented: $showImport) { DocumentPicker { urls in importSkills(urls) } }
    }

    private func importSkills(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                _ = store.importText(text, suggestedName: url.deletingPathExtension().lastPathComponent)
            } else if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                _ = store.importText(text, suggestedName: url.deletingPathExtension().lastPathComponent)
            }
        }
    }
}

private struct SkillDetailView: View {
    let skill: Skill
    var body: some View {
        GlassScreen(title: skill.name) {
            GlassSection(title: "Summary") { Text(skill.summary).font(.caption).foregroundStyle(.white.opacity(0.72)) }
            GlassSection(title: "Tools") { Text(skill.tools.isEmpty ? "Any relevant tool" : skill.tools.joined(separator: ", ")).font(.caption).foregroundStyle(.white.opacity(0.72)) }
            GlassSection(title: "Knowledge / Context / Brain") {
                Text(skill.content).font(.caption).foregroundStyle(.white.opacity(0.72))
            }
            if !skill.executionScripts.isEmpty {
                GlassSection(title: "Execution scripts") {
                    ForEach(skill.executionScripts, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.7)) }
                }
            }
        }
    }
}

private struct SkillEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var format = "md"
    @State private var summary = ""
    @State private var content = ""
    @State private var tools = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("Skill name", text: $name)
                Picker("Format", selection: $format) { Text("MD").tag("md"); Text("SKILL").tag("skill"); Text("JSON").tag("json"); Text("TXT").tag("txt") }
                TextField("Summary", text: $summary)
                TextField("Tools (comma separated)", text: $tools)
                Section("Knowledge, capabilities, context, brain and execution notes") {
                    TextEditor(text: $content).frame(minHeight: 220)
                }
            }
            .navigationTitle("Create Skill")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        _ = SkillStore.shared.create(name: name, format: format, summary: summary.isEmpty ? "Custom skill" : summary, content: content, tools: tools.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
