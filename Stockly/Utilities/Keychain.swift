import Foundation
import Security

enum Keychain {
    private static let service = "com.stockly.apikeys"

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Keychain {
    static var openAIKey: String? {
        get { load(for: "openai_api_key") }
        set {
            if let val = newValue, !val.isEmpty { save(val, for: "openai_api_key") }
            else { delete(for: "openai_api_key") }
        }
    }

    static var claudeKey: String? {
        get { load(for: "claude_api_key") }
        set {
            if let val = newValue, !val.isEmpty { save(val, for: "claude_api_key") }
            else { delete(for: "claude_api_key") }
        }
    }
}
