import Foundation
import Security
import TajpoCore

protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
    /// A display hint such as "sk-…abcd" if a key is saved, without reading the secret.
    func savedKeyHint() -> String?
}

struct KeychainAPIKeyStore: APIKeyStoring {
    static let service = "com.trainabit.tajpo"
    /// Service name used by versions before 0.2; migrated on first load.
    static let legacyService = "com.tajpo.app"
    private let account = "openai-api-key"

    func load() throws -> String? {
        if let key = try read(service: Self.service) { return key }
        guard let legacy = try read(service: Self.legacyService) else { return nil }
        try save(legacy)
        try? deleteItem(service: Self.legacyService)
        return legacy
    }

    func save(_ value: String) throws {
        let key = try APIKeyValidator.validate(value)
        let data = Data(key.utf8)
        let hint = APIKeyValidator.hint(for: key)
        // Update in place so a failed write never loses the existing key.
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrComment as String: hint]
        var status = SecItemUpdate(query(service: Self.service) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(service: Self.service)
            add[kSecValueData as String] = data
            add[kSecAttrComment as String] = hint
            add[kSecAttrLabel as String] = "Tajpo OpenAI API key"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    func delete() throws {
        try deleteItem(service: Self.service)
        try deleteItem(service: Self.legacyService)
    }

    func savedKeyHint() -> String? {
        for service in [Self.service, Self.legacyService] {
            var request = query(service: service)
            request[kSecReturnAttributes as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { continue }
            let attributes = result as? [String: Any]
            return attributes?[kSecAttrComment as String] as? String ?? "Saved"
        }
        return nil
    }

    private func read(service: String) throws -> String? {
        var request = query(service: service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.error(status) }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(service: String) throws {
        let status = SecItemDelete(query(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    private func query(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func error(_ status: OSStatus) -> TajpoError {
        .keychain(status: status, message: SecCopyErrorMessageString(status, nil) as String?)
    }
}
