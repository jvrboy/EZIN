import SwiftUI

/// Manage AI provider API keys. Unlimited keys per provider — EZIN rotates through them.
struct APIKeysView: View {
    @ObservedObject private var store = APIKeyStore.shared
    @State private var editing: CredentialKey?
    private var providers: [CredentialKey] { CredentialKey.allCases.filter { $0.isAIProvider } }

    var body: some View {
        GlassScreen(title: "AI API Keys") {
            GlassSection(title: "Providers") {
                ForEach(Array(providers.enumerated()), id: \.element.id) { idx, key in
                    Button { editing = key } label: {
                        HStack {
                            Image(systemName: store.count(for: key) > 0 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.count(for: key) > 0 ? Glass.buy : .white.opacity(0.3))
                            Text(key.display).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text(store.count(for: key) == 0 ? "Add" : "\(store.count(for: key)) key\(store.count(for: key) == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(Glass.accent2)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if idx < providers.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                }
            }

            Text("Add as many keys per provider as you like — EZIN rotates through them automatically (round-robin) so you never hit a single-key limit. Keys are stored in the device Keychain and never leave your phone.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
        .sheet(item: $editing) { key in ProviderKeysEditor(providerKey: key) }
    }
}

struct ProviderKeysEditor: View {
    let providerKey: CredentialKey
    @ObservedObject private var store = APIKeyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        ZStack {
            Glass.bgBottom.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("\(providerKey.display) Keys").font(.headline).foregroundStyle(.white)
                        Spacer()
                        Button("Done") { dismiss() }.foregroundStyle(Glass.accent2)
                    }

                    let keys = store.keys(for: providerKey)
                    if keys.isEmpty {
                        Text("No keys yet. Add one below.").font(.caption).foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(Array(keys.enumerated()), id: \.offset) { idx, k in
                            HStack {
                                Text(masked(k)).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Button { store.remove(at: idx, for: providerKey) } label: {
                                    Image(systemName: "trash").foregroundStyle(Glass.sell)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                        }
                    }

                    GlassField(placeholder: "Paste API key", text: $draft, secure: true)
                    Button {
                        store.add(draft, for: providerKey); draft = ""
                    } label: {
                        Text("Add key").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Glass.accent.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(20)
            }
        }
    }

    private func masked(_ s: String) -> String {
        guard s.count > 8 else { return String(repeating: "•", count: max(s.count, 3)) }
        return "\(s.prefix(4))••••••\(s.suffix(4))"
    }
}
