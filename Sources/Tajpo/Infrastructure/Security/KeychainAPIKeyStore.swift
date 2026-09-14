import Foundation
import Security

protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

struct KeychainAPIKeyStore: APIKeyStoring {
    private let service = "com.tajpo.app"
    private let account = "openai-api-key"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TajpoError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        try deleteIgnoringMissing()
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TajpoError.keychain(status) }
    }

    func delete() throws { try deleteIgnoringMissing() }

    private func deleteIgnoringMissing() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TajpoError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
