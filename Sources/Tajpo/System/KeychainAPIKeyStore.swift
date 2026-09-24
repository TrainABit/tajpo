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
    static let defaultService = "com.trainabit.tajpo"
    /// Test bundles and development builds get an isolated Keychain service.
    static var service: String { Bundle.main.bundleIdentifier ?? defaultService }
    /// Service name used by versions before 0.2; migrated on first load.
    static let legacyService = "com.tajpo.app"
    private let account = "openai-api-key"

    private var migrationServices: [String] {
        service == Self.defaultService ? [service, Self.legacyService] : [service]
    }

    func load() throws -> String? {
        if let key = try read(service: Self.service) { return key }
        for legacyService in migrationServices where legacyService != Self.service {
            guard let legacy = try read(service: legacyService) else { continue }
            try save(legacy)
            try? deleteItem(service: legacyService)
            return legacy
        }
        return nil
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
        for service in migrationServices { try deleteItem(service: service) }
    }

    func savedKeyHint() -> String? {
        for service in migrationServices {
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
