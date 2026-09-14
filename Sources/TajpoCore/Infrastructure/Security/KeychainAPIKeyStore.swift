import Foundation
import Security

public protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.tajpo.app", account: String = "openai-api-key") {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TajpoError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String) throws {
        let value = try APIKeyValidator.validate(value)
        try deleteIgnoringMissing()
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TajpoError.keychain(status) }
    }

    public func delete() throws { try deleteIgnoringMissing() }

    private func deleteIgnoringMissing() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TajpoError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(value: String? = nil) {
        self.value = value
    }

    public func load() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func save(_ value: String) throws {
        let value = try APIKeyValidator.validate(value)
        lock.lock(); defer { lock.unlock() }
        self.value = value
    }

    public func delete() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}
