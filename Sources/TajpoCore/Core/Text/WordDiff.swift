import Foundation

/// Word-level diff used by the inline panel's diff view. Mirrors the Studio
/// engine's `wordDiff` so both platforms render the same token stream.
public enum WordDiff {
    public enum Kind: Equatable, Sendable {
        case same
        case added
        case removed
    }

    public struct Token: Equatable, Sendable {
        public let text: String
        public let kind: Kind

        public init(text: String, kind: Kind) {
            self.text = text
            self.kind = kind
        }
    }

    /// Splits text into word tokens and whitespace-run tokens, mirroring the
    /// TS engine's whitespace-splitting capture-group behavior.
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        var space = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !word.isEmpty {
                    tokens.append(word)
                    word = ""
                }
                space.unicodeScalars.append(scalar)
            } else {
                if !space.isEmpty {
                    tokens.append(space)
                    space = ""
                }
                word.unicodeScalars.append(scalar)
            }
        }
        if !word.isEmpty { tokens.append(word) }
        if !space.isEmpty { tokens.append(space) }
        return tokens
    }

    /// Greedy token diff with Set-based membership lookups so long documents
    /// stay fast (the same approach as the TS engine).
    public static func tokens(original: String, rewritten: String) -> [Token] {
        let left = tokenize(original)
        let right = tokenize(rewritten)
        let leftSet = Set(left)
        let rightSet = Set(right)
        var result: [Token] = []
        var i = 0
        var j = 0
        while i < left.count || j < right.count {
            if i < left.count, j < right.count, left[i] == right[j] {
                result.append(Token(text: left[i], kind: .same))
                i += 1
                j += 1
                continue
            }
            if j < right.count, !leftSet.contains(right[j]) {
                result.append(Token(text: right[j], kind: .added))
                j += 1
                continue
            }
            if i < left.count, !rightSet.contains(left[i]) {
                result.append(Token(text: left[i], kind: .removed))
                i += 1
                continue
            }
            if i < left.count {
                result.append(Token(text: left[i], kind: .removed))
                i += 1
            }
            if j < right.count {
                result.append(Token(text: right[j], kind: .added))
                j += 1
            }
        }
        return result
    }
}
