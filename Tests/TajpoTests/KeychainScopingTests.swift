import Foundation
import Testing
@testable import TajpoCore

/// In-memory seam mirroring the Keychain store's per-provider account logic so
/// scoping and the legacy migration can be tested without touching the real
/// Keychain (which is unavailable to `swift test` runs).
final class ScopedKeyStoreHarness {
    private var items: [String: String] = [:]

    func save(_ key: String, for provider: LLMProvider) {
        items[KeychainAPIKeyStore.accountName(for: provider)] = key
    }

    /// Writes directly to the shared account used by old builds.
    func saveLegacy(_ key: String) {
        items[KeychainAPIKeyStore.legacyAccount] = key
    }

    /// Mirrors KeychainAPIKeyStore.loadMigratingLegacy().
    func load(for provider: LLMProvider) -> String? {
        let account = KeychainAPIKeyStore.accountName(for: provider)
        if let scoped = items[account] { return scoped }
        guard account != KeychainAPIKeyStore.legacyAccount else { return nil }
        guard let legacy = items[KeychainAPIKeyStore.legacyAccount], !legacy.isEmpty else { return nil }
        items[account] = legacy
        items.removeValue(forKey: KeychainAPIKeyStore.legacyAccount)
        return legacy
    }
}

@Test func keychainAccountsAreScopedPerProvider() {
    #expect(KeychainAPIKeyStore.accountName(for: .openAI) == "api-key-openAI")
    #expect(KeychainAPIKeyStore.accountName(for: .localCompatible) == "api-key-localCompatible")
    #expect(KeychainAPIKeyStore.accountName(for: .openAI) != KeychainAPIKeyStore.accountName(for: .localCompatible))
    #expect(KeychainAPIKeyStore.accountName(for: .openAI) != KeychainAPIKeyStore.legacyAccount)
}

@Test func differentProvidersKeepDistinctKeys() {
    let harness = ScopedKeyStoreHarness()
    harness.save("sk-openai", for: .openAI)
    harness.save("sk-local", for: .localCompatible)
    #expect(harness.load(for: .openAI) == "sk-openai")
    #expect(harness.load(for: .localCompatible) == "sk-local")
}

@Test func legacyKeyMigratesIntoScopedAccountOnLoad() {
    let harness = ScopedKeyStoreHarness()
    // A key written by an old build under the shared account...
    harness.saveLegacy("sk-legacy")
    // ...migrates into the current provider's scoped account on first load.
    #expect(harness.load(for: .openAI) == "sk-legacy")
    // Migrated once: the legacy account is cleared, so another provider finds nothing...
    #expect(harness.load(for: .localCompatible) == nil)
    // ...while the scoped account keeps owning the key.
    #expect(harness.load(for: .openAI) == "sk-legacy")
}
