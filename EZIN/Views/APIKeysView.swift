import SwiftUI

/// Manage AI provider API keys. Saved to Keychain so users never re-enter them.
struct APIKeysView: View {
    @ObservedObject private var creds = CredentialStore.shared
    @State private var editing: CredentialKey?
    @State private var draft = ""

    private var providers: [CredentialKey] { CredentialKey.allCases.filter { $0.isAIProvider } }

    var body: some View {
        GlassScreen(title: "AI API Keys") {
            GlassSection(title: "Providers") {
                ForEach(Array(providers.enumerated()), id: \.element.id) { idx, key in
                    HStack {
                        Image(systemName: creds.has(key) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(creds.has(key) ? Glass.buy : .white.opacity(0.3))
                        Text(key.display).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                        Spacer()
                        if creds.has(key) {
                            Button("Remove") { creds.remove(key) }
                                .font(.caption).foregroundStyle(Glass.sell)
                        }
                        Button(creds.has(key) ? "Edit" : "Add") { editing = key; draft = "" }
                            .font(.caption).foregroundStyle(Glass.accent2)
                    }
                    .padding(.vertical, 10)
                    if idx < providers.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                }
            }

            Text("Keys are stored securely in the device Keychain and never leave your phone.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
        .sheet(item: $editing) { key in keyEditor(key) }
    }

    private func keyEditor(_ key: CredentialKey) -> some View {
        ZStack {
            Glass.bgBottom.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("\(key.display) API Key").font(.headline).foregroundStyle(.white)
                GlassField(placeholder: "Paste API key", text: $draft, secure: true)
                Button {
                    if !draft.isEmpty { creds.set(draft, for: key) }
                    editing = nil
                } label: {
                    Text("Save").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Glass.accent.opacity(0.7)))
                }.buttonStyle(.plain)
                Spacer()
            }.padding(20)
        }
    }
}
