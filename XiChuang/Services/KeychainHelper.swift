import Foundation
import Security

/// 把 Claude API Key 存进钥匙串，而不是 UserDefaults。
enum KeychainHelper {
    private static let service = "app.xichuang.claude"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(baseQuery as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var query = baseQuery
            query[kSecValueData as String] = Data(newValue.utf8)
            // 后台任务在锁屏时也要能读到
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static var hasAPIKey: Bool { !(apiKey ?? "").isEmpty }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
