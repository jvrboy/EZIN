import SwiftUI

/// Conversation history: search, pin, rename, archive, delete, add-to-project.
struct ConversationsListView: View {
    @ObservedObject private var store = ConversationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var renameTarget: Conversation?
    @State private var showArchived = false
    @State private var showBin = false

    private var filtered: [Conversation] {
        let base = showArchived ? store.archivedList : store.active
        guard !search.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    private var binItems: [BinItem] {
        guard !search.isEmpty else { return store.bin }
        return store.bin.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationView {
            List {
                if !showArchived {
                    Section {
                        Button {
                            store.newConversation(); dismiss()
                        } label: {
                            Label("New chat", systemImage: "square.and.pencil").foregroundStyle(Glass.accent)
                        }
                    }
                }
                if showBin {
                    Section("Recoverable bin") {
                        if binItems.isEmpty {
                            Text("Bin is empty. Deleted chats and projects land here before permanent removal.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(binItems) { item in binRow(item) }
                        if !store.bin.isEmpty {
                            Button(role: .destructive) { store.emptyBin() } label: {
                                Label("Empty bin permanently", systemImage: "trash.slash")
                            }
                        }
                    }
                } else {
                    Section(showArchived ? "Archived" : "Conversations") {
                        if filtered.isEmpty {
                            Text(showArchived ? "No archived chats." : "No conversations yet.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(filtered) { c in row(c) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Search chats")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Active") { showArchived = false; showBin = false }
                        Button("Archived") { showArchived = true; showBin = false }
                        Button("Bin") { showBin = true }
                    } label: {
                        Text(showBin ? "Bin" : (showArchived ? "Archived" : "Active"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $renameTarget) { c in
                RenameSheet(title: "Rename chat", initial: c.title) { store.rename(c.id, to: $0) }
            }
        }
    }

    private func binRow(_ item: BinItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.contains("project") ? "folder.fill" : "bubble.left")
                .foregroundStyle(item.type.contains("project") ? Glass.accent2 : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text("\(item.type.replacingOccurrences(of: "archived", with: "archived ")) · \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { store.deleteBinItem(item) } label: { Label("Delete forever", systemImage: "trash.slash") }
            Button { store.restoreBinItem(item); dismiss() } label: { Label("Restore", systemImage: "arrow.uturn.backward") }.tint(Glass.buy)
        }
    }

    private func row(_ c: Conversation) -> some View {
        Button {
            store.select(c.id); dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: c.pinned ? "pin.fill" : "bubble.left")
                    .foregroundStyle(c.pinned ? Glass.accent : .secondary).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Text(c.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let pid = c.projectID, let p = store.project(pid) {
                        Text("Project · \(p.name)").font(.system(size: 10)).foregroundStyle(Glass.accent2)
                    }
                }
                Spacer()
                if c.id == store.currentID { Circle().fill(Glass.accent).frame(width: 7, height: 7) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { store.delete(c.id) } label: { Label("Delete", systemImage: "trash") }
            Button { store.toggleArchive(c.id) } label: {
                Label(c.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }.tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { store.togglePin(c.id) } label: {
                Label(c.pinned ? "Unpin" : "Pin", systemImage: c.pinned ? "pin.slash" : "pin")
            }.tint(Glass.accent)
            Button { renameTarget = c } label: { Label("Rename", systemImage: "pencil") }.tint(.gray)
        }
        .contextMenu {
            Button { renameTarget = c } label: { Label("Rename", systemImage: "pencil") }
            Button { store.togglePin(c.id) } label: { Label(c.pinned ? "Unpin" : "Pin", systemImage: "pin") }
            Button { store.toggleArchive(c.id) } label: { Label(c.archived ? "Unarchive" : "Archive", systemImage: "archivebox") }
            Menu {
                Button("None") { store.assign(c.id, toProject: nil) }
                ForEach(store.projects) { p in
                    Button(p.name) { store.assign(c.id, toProject: p.id) }
                }
            } label: { Label("Add to project", systemImage: "folder.badge.plus") }
            Button(role: .destructive) { store.delete(c.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// Reusable rename sheet (works on iOS 15 — avoids alert-with-TextField which is iOS 16+).
struct RenameSheet: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, onSave: @escaping (String) -> Void) {
        self.title = title; self._text = State(initialValue: initial); self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 20)
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
