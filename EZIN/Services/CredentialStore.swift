import Foundation
import Security

/// Securely stores AI API keys / Deriv tokens in the iOS Keychain so the user
/// never has to re-enter them. Persists across launches on-device.
/// Items are marked ThisDeviceOnly so trading tokens never sync to iCloud Keychain.
final class CredentialStore: ObservableObject {
    static let shared = CredentialStore()
    private let service = "com.ezin.credentials"
    @Published private(set) var configured: Set<CredentialKey> = []

    private init() { refresh() }

    func set(_ value: String, for key: CredentialKey) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
        refresh()
    }

    func value(for key: CredentialKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: CredentialKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        refresh()
    }

    func has(_ key: CredentialKey) -> Bool { configured.contains(key) }

    private func refresh() {
        configured = Set(CredentialKey.allCases.filter { value(for: $0) != nil })
    }
}
