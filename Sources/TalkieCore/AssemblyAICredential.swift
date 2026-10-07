import Foundation
import Security

enum AssemblyAICredential {
    static let service = "nl.bentjes.talkie.assemblyai"
    static let account = "api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ key: String) -> String? {
        let status: OSStatus
        if key.isEmpty {
            status = SecItemDelete(query as CFDictionary)
        } else {
            let attributes = [kSecValueData as String: Data(key.utf8)]
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if update == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            } else {
                status = update
            }
        }
        guard status != errSecSuccess && status != errSecItemNotFound else { return nil }
        return "Could not save the AssemblyAI key in Keychain (\(status))."
    }
}
