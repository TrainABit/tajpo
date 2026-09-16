import Testing
@testable import TajpoCore

@Test func emptySelectionIsRejected() {
    #expect(throws: TajpoError.noSelection) {
        try SelectionValidator.validate("   \n\t")
    }
}

@Test func oversizedSelectionIsRejected() {
    #expect(throws: TajpoError.textTooLarge) {
        try SelectionValidator.validate(String(repeating: "a", count: SelectionValidator.maximumCharacters + 1))
    }
}

@Test func validSelectionIsAccepted() throws {
    try SelectionValidator.validate("Hello there")
}

@Test func emptyAPIKeyIsRejected() {
    #expect(throws: TajpoError.missingAPIKey) {
        try APIKeyValidator.validate("   ")
    }
}

@Test func apiKeyIsTrimmed() throws {
    #expect(try APIKeyValidator.validate("  sk-test  ") == "sk-test")
}

@Test func inMemoryKeyStoreRoundTrip() throws {
    let store = InMemoryAPIKeyStore()
    try store.save(" sk-live ")
    #expect(try store.load() == "sk-live")
    try store.delete()
    #expect(try store.load() == nil)
}
