import Foundation
import Security

/// 把各家解析服务的 API Key 存进钥匙串，而不是 UserDefaults。
enum KeychainHelper {
    private static let service = "app.xichuang.claude"

    static func apiKey(for provider: AnalysisProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAPIKey(_ key: String?, for provider: AnalysisProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var query = baseQuery(provider)
        query[kSecValueData as String] = Data(key.utf8)
        // 后台任务在锁屏时也要能读到
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func hasAPIKey(for provider: AnalysisProvider) -> Bool {
        !(apiKey(for: provider) ?? "").isEmpty
    }

    private static func baseQuery(_ provider: AnalysisProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
    }
}
