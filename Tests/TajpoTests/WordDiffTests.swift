import Foundation
import Testing
@testable import TajpoCore

@Suite struct WordDiffTests {
    @Test func marksAddedAndRemovedWords() {
        let tokens = WordDiff.tokens(original: "hello world", rewritten: "hello planet")
        #expect(tokens.contains { $0.kind == .removed && $0.text == "world" })
        #expect(tokens.contains { $0.kind == .added && $0.text == "planet" })
        #expect(tokens.contains { $0.kind == .same && $0.text == "hello" })
    }

    @Test func handlesEmptySides() {
        #expect(WordDiff.tokens(original: "", rewritten: "one two").allSatisfy { $0.kind == .added })
        #expect(WordDiff.tokens(original: "one two", rewritten: "").allSatisfy { $0.kind == .removed })
        #expect(WordDiff.tokens(original: "", rewritten: "").isEmpty)
    }

    @Test func tokenizerKeepsWhitespaceRuns() {
        let tokens = WordDiff.tokenize("a  b\nc")
        #expect(tokens == ["a", "  ", "b", "\n", "c"])
    }

    @Test func duplicateTokensStayFast() {
        let tokens = WordDiff.tokens(original: "very very good", rewritten: "very good")
        #expect(tokens.contains { $0.kind == .removed && $0.text == "very" })
        #expect(tokens.contains { $0.kind == .added && $0.text == "good" })
    }

    @Test func longInputsFinishQuickly() {
        let left = (0..<10_000).map { "word\($0)" }.joined(separator: " ")
        let right = (0..<10_000).map { $0 % 7 == 0 ? "changed\($0)" : "word\($0)" }.joined(separator: " ")
        let start = Date()
        let tokens = WordDiff.tokens(original: left, rewritten: right)
        #expect(!tokens.isEmpty)
        #expect(Date().timeIntervalSince(start) < 2.0)
    }
}

@MainActor
@Suite struct HistoryStoreDeleteTests {
    @Test func deletesExactlyOneEntryAndPersists() {
        let suite = UserDefaults(suiteName: "tajpo.tests.history-\(UUID().uuidString)") ?? .standard
        suite.removePersistentDomain(forName: suite.name)
        let store = HistoryStore(defaults: suite, key: "history")
        store.record(action: .correct, tone: .casual, original: "a", result: "b")
        store.record(action: .improve, tone: .professional, original: "c", result: "d")
        #expect(store.entries.count == 2)
        let victim = store.entries[1]
        store.delete(id: victim.id)
        #expect(store.entries.count == 1)
        #expect(store.entries[0].id != victim.id)
        // The removal persists through a fresh store over the same defaults.
        let reloaded = HistoryStore(defaults: suite, key: "history")
        #expect(reloaded.entries.count == 1)
    }
}
