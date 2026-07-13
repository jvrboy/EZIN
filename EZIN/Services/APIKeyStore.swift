import Foundation
import Security
import Combine

/// Stores UNLIMITED API keys per AI provider and rotates through them (round-robin)
/// so a single key's rate limit never blocks the app. Keychain-backed, device-only.
final class APIKeyStore: ObservableObject {
    static let shared = APIKeyStore()
    private let service = "com.ezin.apikeys"
    @Published private(set) var counts: [CredentialKey: Int] = [:]
    private var rr: [CredentialKey: Int] = [:]

    private init() { refresh() }

    func keys(for key: CredentialKey) -> [String] {
        guard let data = raw(for: key),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    func add(_ value: String, for key: CredentialKey) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        var arr = keys(for: key)
        arr.append(v)
        store(arr, for: key)
    }

    func remove(at index: Int, for key: CredentialKey) {
        var arr = keys(for: key)
        guard arr.indices.contains(index) else { return }
        arr.remove(at: index)
        store(arr, for: key)
    }

    func count(for key: CredentialKey) -> Int { keys(for: key).count }

    var totalKeys: Int { counts.values.reduce(0, +) }

    /// Next key for a provider in round-robin order (spreads load across all keys).
    func next(for key: CredentialKey) -> String? {
        let arr = keys(for: key)
        guard !arr.isEmpty else { return nil }
        let i = (rr[key] ?? 0) % arr.count
        rr[key] = i + 1
        return arr[i]
    }

    /// Providers that currently have at least one key.
    var activeProviders: [CredentialKey] {
        CredentialKey.allCases.filter { $0.isAIProvider && count(for: $0) > 0 }
    }

    // MARK: - Keychain
    private func store(_ arr: [String], for key: CredentialKey) {
        let account = key.rawValue + ".keys"
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        if !arr.isEmpty, let data = try? JSONEncoder().encode(arr) {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
        refresh()
    }

    private func raw(for key: CredentialKey) -> Data? {
        let account = key.rawValue + ".keys"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return nil }
        return d
    }

    private func refresh() {
        var c: [CredentialKey: Int] = [:]
        for k in CredentialKey.allCases where k.isAIProvider { c[k] = keys(for: k).count }
        counts = c
    }
}
