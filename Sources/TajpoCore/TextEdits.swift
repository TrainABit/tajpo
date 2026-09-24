import Foundation

public enum OutputCleaner {
    /// Turns raw model output into replacement text for `original`:
    /// removes echoed delimiter tags and wrapping quotes or code fences the
    /// original didn't have, then restores the original's leading and trailing
    /// whitespace (e.g. the newline of a triple-clicked paragraph).
    public static func finalize(_ output: String, original: String, tag: String = "text") -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripTags(text, tag: tag)
        text = stripCodeFence(text, original: original)
        text = stripWrappingQuotes(text, original: original)
        return WhitespacePreserver.apply(original: original, to: text)
    }

    static func stripTags(_ text: String, tag: String) -> String {
        let open = "<\(tag)>", close = "</\(tag)>"
        guard text.hasPrefix(open), text.hasSuffix(close), text.count >= open.count + close.count else { return text }
        return String(text.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripCodeFence(_ text: String, original: String) -> String {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```"), text.hasSuffix("```"), !trimmedOriginal.hasPrefix("```"),
              let firstNewline = text.firstIndex(of: "\n") else { return text }
        let body = text[text.index(after: firstNewline)...].dropLast(3)
        return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("„", "“"), ("«", "»"), ("'", "'"), ("‘", "’")]

    static func stripWrappingQuotes(_ text: String, original: String) -> String {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, let first = text.first, let last = text.last else { return text }
        for (open, close) in quotePairs where first == open && last == close {
            if trimmedOriginal.first == open && trimmedOriginal.last == close { return text }
            let inner = text.dropFirst().dropLast()
            // Only strip if the quotes wrap the whole text, not two quoted phrases.
            if !inner.contains(close) || open == close && !inner.contains(open) {
                return String(inner)
            }
        }
        return text
    }
}

public enum OutputValidator {
    /// Validates the text after wrappers and original whitespace have been
    /// removed. A non-empty selection may never be replaced by an empty or
    /// whitespace-only result, and a Shorten action may not expand without
    /// bound.
    public static func validate(
        _ text: String,
        action: RewriteAction,
        original: String
    ) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TajpoError.emptyResponse
        }
        guard action == .shorten else { return }

        let originalLength = max(1, original.trimmingCharacters(in: .whitespacesAndNewlines).count)
        let outputLength = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maximum = max(originalLength + 200, originalLength * 2)
        guard outputLength <= maximum else {
            throw TajpoError.api("The Shorten result expanded beyond a safe limit and cannot be replaced automatically.")
        }
    }
}

public enum WhitespacePreserver {
    /// Re-applies `original`'s leading and trailing whitespace to `text`.
    public static func apply(original: String, to text: String) -> String {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let leading = original.prefix { $0.isWhitespace }
        let trailing = original.reversed().prefix { $0.isWhitespace }.reversed()
        if original.allSatisfy(\.isWhitespace) { return core }
        return String(leading) + core + String(trailing)
    }
}

public struct DiffSegment: Equatable, Sendable {
    public enum Kind: Sendable { case same, inserted, removed }
    public let kind: Kind
    public let text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum WordDiff {
    /// Above this many tokens per side the diff is skipped (it's O(n·m)).
    public static let maximumTokens = 1_500

    /// Splits into words, whitespace runs, and single punctuation marks.
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
            currentIsSpace = nil
        }
        for character in text {
            if character.isLetter || character.isNumber || character == "'" || character == "’" {
                if currentIsSpace != false { flush() }
                currentIsSpace = false
                current.append(character)
            } else if character.isWhitespace {
                if currentIsSpace != true { flush() }
                currentIsSpace = true
                current.append(character)
            } else {
                flush()
                tokens.append(String(character))
            }
        }
        flush()
        return tokens
    }

    /// Word-level diff, or `nil` if the texts are too long to diff quickly.
    public static func diff(from old: String, to new: String) -> [DiffSegment]? {
        let a = tokenize(old), b = tokenize(new)
        guard a.count <= maximumTokens, b.count <= maximumTokens else { return nil }
        let n = a.count, m = b.count
        var lengths = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
                }
            }
        }
        var segments: [DiffSegment] = []
        func append(_ kind: DiffSegment.Kind, _ text: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = DiffSegment(kind, last.text + text)
            } else {
                segments.append(DiffSegment(kind, text))
            }
        }
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                append(.same, a[i]); i += 1; j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                append(.removed, a[i]); i += 1
            } else {
                append(.inserted, b[j]); j += 1
            }
        }
        while i < n { append(.removed, a[i]); i += 1 }
        while j < m { append(.inserted, b[j]); j += 1 }
        return segments
    }
}
