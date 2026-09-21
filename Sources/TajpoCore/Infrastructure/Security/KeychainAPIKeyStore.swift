import Foundation
import Security

public protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    /// Keys written before per-provider scoping used this shared account.
    public static let legacyAccount = "openai-api-key"

    private let service: String
    private let account: String

    public init(service: String = "com.tajpo.app", account: String = KeychainAPIKeyStore.legacyAccount) {
        self.service = service
        self.account = account
    }

    /// Scopes the Keychain account to a provider so keys for different providers
    /// do not overwrite each other.
    public init(service: String = "com.tajpo.app", provider: LLMProvider) {
        self.init(service: service, account: Self.accountName(for: provider))
    }

    public static func accountName(for provider: LLMProvider) -> String {
        "api-key-\(provider.rawValue)"
    }

    /// Loads the scoped key, falling back to the legacy shared account.
    /// The legacy item is migrated into the scoped account and removed so each
    /// provider owns a distinct item afterwards.
    public func loadMigratingLegacy() throws -> String? {
        if let scoped = try load() { return scoped }
        guard account != Self.legacyAccount else { return nil }
        let legacy = KeychainAPIKeyStore(service: service, account: Self.legacyAccount)
        guard let value = try legacy.load(), !value.isEmpty else { return nil }
        try save(value)
        try? legacy.delete()
        return value
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
