import SwiftUI

/// Projects: each project is an on-device folder whose files are shared with every
/// conversation created inside it. Create projects, add files, start project chats.
struct ProjectsView: View {
    @ObservedObject private var store = ConversationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button { showNew = true } label: {
                        Label("New project", systemImage: "folder.badge.plus").foregroundStyle(Glass.accent)
                    }
                }
                Section("Projects") {
                    if store.projects.isEmpty {
                        Text("No projects yet. A project is a folder whose files are shared with all its chats.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(store.projects) { p in
                        NavigationLink { ProjectDetailView(projectID: p.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill").foregroundStyle(Glass.accent2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 15, weight: .medium))
                                    Text("\(store.conversations(inProject: p.id).count) chats · \(p.files.count) files")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.deleteProject(p.id) } label: { Label("Delete", systemImage: "trash") }
                            Button { store.archiveProject(p.id) } label: { Label("Archive", systemImage: "archivebox") }.tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Projects")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showNew) {
                RenameSheet(title: "New project", initial: "") { store.addProject(name: $0) }
            }
        }
    }
}

struct ProjectDetailView: View {
    let projectID: UUID
    @ObservedObject private var store = ConversationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var showRename = false

    private var project: ChatProject? { store.project(projectID) }

    var body: some View {
        List {
            if let p = project {
                Section {
                    Button {
                        store.newConversation(projectID: p.id); dismiss()
                    } label: { Label("New chat in project", systemImage: "square.and.pencil").foregroundStyle(Glass.accent) }
                    Button { showPicker = true } label: { Label("Add file", systemImage: "doc.badge.plus") }
                }
                Section("Files (shared with all chats)") {
                    if p.files.isEmpty { Text("No files yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(p.files, id: \.self) { f in
                        Label(f, systemImage: "doc").font(.system(size: 14))
                    }
                }
                Section("Conversations") {
                    let convos = store.conversations(inProject: p.id)
                    if convos.isEmpty { Text("No chats yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(convos) { c in
                        Button { store.select(c.id) } label: {
                            HStack {
                                Text(c.title).font(.system(size: 14))
                                Spacer()
                                if c.id == store.currentID { Circle().fill(Glass.accent).frame(width: 7, height: 7) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button { store.archiveProject(projectID); dismiss() } label: { Label("Archive project", systemImage: "archivebox") }
                    Button(role: .destructive) { store.deleteProject(projectID); dismiss() } label: { Label("Delete project", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: "Rename project", initial: project?.name ?? "") { store.renameProject(projectID, to: $0) }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in importFiles(urls) }
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard let p = project else { return }
        let folder = FileStore.shared.projectFolder(p)
        for src in urls {
            let dest = folder.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil {
                store.addFile(src.lastPathComponent, toProject: p.id)
            }
        }
    }
}
