import Foundation
import Security

// Config de la app: base URL (UserDefaults), API token (Keychain, NUNCA
// hardcodeado), cursor de sync (UserDefaults), y el flag de mock del API client.
@Observable
final class AppConfig {
    static let shared = AppConfig()

    private let d = UserDefaults.standard

    var baseURL: String {
        get { d.string(forKey: "cbum.baseURL") ?? "" }
        set { d.set(newValue, forKey: "cbum.baseURL") }
    }

    /// Cursor incremental de /api/changes (0 la primera vez).
    var syncCursor: Int {
        get { d.integer(forKey: "cbum.syncCursor") }
        set { d.set(newValue, forKey: "cbum.syncCursor") }
    }

    /// Usa el mock local del API client (desarrollo sin backend). Intercambiable.
    var useMockAPI: Bool {
        get { d.object(forKey: "cbum.useMock") as? Bool ?? true }
        set { d.set(newValue, forKey: "cbum.useMock") }
    }

    var lastSyncAt: Date? {
        get { let t = d.double(forKey: "cbum.lastSyncAt"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { d.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "cbum.lastSyncAt") }
    }

    // API token en Keychain
    private let tokenAccount = "cbum.apiToken"

    var apiToken: String {
        get { Keychain.read(account: tokenAccount) ?? "" }
        set {
            if newValue.isEmpty { Keychain.delete(account: tokenAccount) }
            else { Keychain.write(newValue, account: tokenAccount) }
        }
    }

    var isConfigured: Bool { !baseURL.isEmpty && !apiToken.isEmpty }
}

// Wrapper mínimo de Keychain (sin dependencias).
enum Keychain {
    private static let service = "com.mackley.cbum"

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
