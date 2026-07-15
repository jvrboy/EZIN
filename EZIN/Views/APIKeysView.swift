import SwiftUI

/// Manage AI provider API keys. Unlimited keys per provider — EZIN rotates through them.
/// Now includes real-time token usage tracking and rate-limit status.
struct APIKeysView: View {
    @ObservedObject private var store = APIKeyStore.shared
    @ObservedObject private var tracker = APITokenTracker.shared
    @State private var editing: CredentialKey?
    private var providers: [CredentialKey] { CredentialKey.allCases.filter { $0.isAIProvider } }

    var body: some View {
        GlassScreen(title: "AI API Keys") {
            // Provider aggregate stats
            if !tracker.providerTotals.isEmpty {
                GlassSection(title: "Live Usage") {
                    ForEach(Array(tracker.providerTotals.keys.sorted { $0.display < $1.display }), id: \.self) { provider in
                        let stats = tracker.providerTotals[provider]!
                        HStack {
                            Text(provider.display)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text(stats.summary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(stats.activeKeys > 0 ? Glass.buy : Glass.sell)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            GlassSection(title: "Providers") {
                ForEach(Array(providers.enumerated()), id: \.element.id) { idx, key in
                    ProviderRow(
                        key: key,
                        keyCount: store.count(for: key),
                        isEditing: editing == key
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editing = key }
                    if idx < providers.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
                }
            }

            Text("Add as many keys per provider as you like — EZIN rotates through them automatically (round-robin) so you never hit a single-key limit. Keys are stored in the device Keychain and never leave your phone. Token usage is tracked per key.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
        .sheet(item: $editing) { key in ProviderKeysEditor(providerKey: key) }
        .onAppear { tracker.checkDayRollover() }
    }
}

struct ProviderRow: View {
    let key: CredentialKey
    let keyCount: Int
    let isEditing: Bool
    @ObservedObject private var tracker = APITokenTracker.shared

    var body: some View {
        HStack {
            Image(systemName: keyCount > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(keyCount > 0 ? Glass.buy : .white.opacity(0.3))
            Text(key.display).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88))
            Spacer()
            // Show rate-limit or health indicator
            if keyCount > 0, let stats = tracker.providerTotals[key] {
                if stats.rateLimitedKeys > 0 {
                    Text("\(stats.rateLimitedKeys) limited")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(keyCount == 0 ? "Add" : "\(keyCount) key\(keyCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(Glass.accent2)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
    }
}

struct ProviderKeysEditor: View {
    let providerKey: CredentialKey
    @ObservedObject private var store = APIKeyStore.shared
    @ObservedObject private var tracker = APITokenTracker.shared
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

                    // Usage stats for this provider
                    let stats = tracker.aggregate(for: providerKey)
                    if stats.totalKeys > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Usage Summary").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                            Text(stats.summary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(stats.activeKeys > 0 ? Glass.buy : Glass.sell)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                    }

                    let keys = store.keys(for: providerKey)
                    if keys.isEmpty {
                        Text("No keys yet. Add one below.").font(.caption).foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(Array(keys.enumerated()), id: \.offset) { idx, k in
                            KeyRow(
                                key: k,
                                index: idx,
                                provider: providerKey,
                                onDelete: { store.remove(at: idx, for: providerKey) }
                            )
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
}

struct KeyRow: View {
    let key: String
    let index: Int
    let provider: CredentialKey
    let onDelete: () -> Void
    @ObservedObject private var tracker = APITokenTracker.shared

    private var keyId: String {
        String(key.prefix(8)) + "..." + String(key.suffix(4))
    }

    private var isHealthy: Bool {
        tracker.isKeyUsable(provider: provider, keyId: keyId)
    }

    var body: some View {
        HStack {
            Circle()
                .fill(isHealthy ? Glass.buy : Glass.sell)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(masked(key))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))

                // Per-key usage stats
                if let stats = tracker.keyStats["\(provider.rawValue).\(keyId)"] {
                    HStack(spacing: 8) {
                        if stats.totalRequests > 0 {
                            Text("\(stats.totalRequests) req")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        if stats.tokensUsed > 0 {
                            Text("\(stats.tokensUsed) tok")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        if let remaining = stats.rateLimitRemaining {
                            Text("\(remaining) left")
                                .font(.system(size: 9))
                                .foregroundStyle(Glass.accent2.opacity(0.7))
                        }
                        if stats.isRateLimited {
                            Text("RATE LIMITED")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        if let lastUsed = stats.lastUsedAt {
                            Text(timeAgo(lastUsed))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }

            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundStyle(Glass.sell)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private func masked(_ s: String) -> String {
        guard s.count > 8 else { return String(repeating: "•", count: max(s.count, 3)) }
        return "\(s.prefix(4))••••••\(s.suffix(4))"
    }

    private func timeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        return "\(Int(diff / 3600))h ago"
    }
}
