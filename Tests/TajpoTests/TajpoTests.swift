import Testing
@testable import Tajpo

@Test func actionTitlesExist() { #expect(RewriteAction.allCases.allSatisfy { !$0.title.isEmpty }) }
