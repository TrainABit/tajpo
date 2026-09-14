import Testing
@testable import TajpoCore

@Test func passwordBulletsAreDetected() {
    #expect(SelectionSafety.looksLikePassword("••••••"))
    #expect(!SelectionSafety.looksLikePassword("hello"))
}

@Test func secureRolesAreDetected() {
    #expect(SelectionSafety.isSecureRole(role: "AXSecureTextField", subrole: "", description: ""))
    #expect(SelectionSafety.isSecureRole(role: "AXTextField", subrole: "AXSecureTextField", description: ""))
    #expect(SelectionSafety.isSecureRole(role: "AXTextField", subrole: "", description: "password"))
    #expect(!SelectionSafety.isSecureRole(role: "AXTextArea", subrole: "", description: "text"))
}

@Test func webAreasBlockClipboardFallback() {
    #expect(!SelectionSafety.allowsClipboardFallback(focusedRole: "AXWebArea"))
    #expect(SelectionSafety.allowsClipboardFallback(focusedRole: "AXTextArea"))
    #expect(SelectionSafety.allowsClipboardFallback(focusedRole: nil))
}

@Test func hostAppMatrixMatchesExpectedDecisions() {
    for item in HostAppMatrix.cases {
        let decision = SelectionSafety.decision(
            focusedRole: item.focusedRole,
            selectedText: item.selectedText,
            ancestorOrDescendantSecure: item.secureContext,
            selectedLooksLikePassword: item.selectedText.map(SelectionSafety.looksLikePassword) ?? false
        )
        #expect(decision == item.expected, "\(item.id) expected \(item.expected), got \(decision)")
    }
}
