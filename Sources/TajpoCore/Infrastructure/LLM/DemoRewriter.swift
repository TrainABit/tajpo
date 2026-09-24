import Foundation

public struct DemoLexicon: Codable, Sendable, Equatable {
    public var typos: [String: String]
    public var filler: [String]
    public var hedges: [String]
    public var wordy: [String: String]
    public var simplify: [String: String]
    public var expandContractions: [String: String]
    public var addContractions: [String: String]
    public var casualSlang: [String: String]
}

public enum DemoLexiconLoader {
    public static func load() -> DemoLexicon {
        if let url = resourceURL(),
           let data = try? Data(contentsOf: url),
           let lexicon = try? JSONDecoder().decode(DemoLexicon.self, from: data) {
            return lexicon
        }
        return fallback
    }

    private static let fallback = DemoLexicon(
        typos: ["teh": "the", "dont": "don't", "im": "I'm"],
        filler: ["just", "really", "very", "actually"],
        hedges: ["I think", "maybe", "perhaps"],
        wordy: ["in order to": "to", "due to the fact that": "because"],
        simplify: ["utilize": "use", "commence": "start"],
        expandContractions: ["don't": "do not", "I'm": "I am"],
        addContractions: ["do not": "don't", "I am": "I'm"],
        casualSlang: ["gonna": "going to"]
    )

    /// Do not touch `Bundle.module` here. Its generated accessor calls
    /// `fatalError` when a packaged app is missing the SwiftPM resource
    /// bundle, which turns a recoverable demo fallback into a process crash.
    /// Packaged builds can place the bundle at the app root or in Contents/Resources.
    private static func resourceURL() -> URL? {
        let fileManager = FileManager.default
        let bundleName = "Tajpo_TajpoCore.bundle"
        var roots: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: DemoLexiconBundleMarker.self).resourceURL,
            Bundle(for: DemoLexiconBundleMarker.self).bundleURL
        ]
        roots.append(contentsOf: Bundle.allBundles.flatMap { [$0.resourceURL, $0.bundleURL] })

        var candidates: [URL] = []
        for root in roots.compactMap({ $0 }) {
            candidates.append(root.appendingPathComponent(bundleName))
            candidates.append(root.appendingPathComponent("Contents/Resources/\(bundleName)"))
        }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate),
               let resource = bundle.url(forResource: "demo-lexicon", withExtension: "json") {
                return resource
            }
            for relativePath in [
                "Contents/Resources/demo-lexicon.json",
                "demo-lexicon.json"
            ] {
                let resource = candidate.appendingPathComponent(relativePath)
                if fileManager.fileExists(atPath: resource.path) { return resource }
            }
        }
        return nil
    }
}

private final class DemoLexiconBundleMarker {}

public struct DemoRewriteExtras: Sendable, Equatable {
    public var length: RewriteLength
    public var preset: WritingPreset?
    public var customInstructions: String

    public init(length: RewriteLength = .same, preset: WritingPreset? = nil, customInstructions: String = "") {
        self.length = length
        self.preset = preset
        self.customInstructions = customInstructions
    }

    public static let empty = DemoRewriteExtras()
}

public enum StyleRules {
    public static func applyCustomInstructions(_ text: String, _ instructions: String) -> String {
        var result = text
        let patterns = [
            #"(?:never use|don't use|do not use|avoid)(?: the word)? ["“]?([A-Za-z][A-Za-z'-]*)["”]?"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: instructions, range: NSRange(location: 0, length: (instructions as NSString).length)),
               let range = Range(match.range(at: 1), in: instructions) {
                let word = String(instructions[range])
                let escaped = NSRegularExpression.escapedPattern(for: word)
                if let wordRegex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) {
                    let ns = result as NSString
                    result = wordRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                }
            }
        }
        if instructions.range(of: "no exclamation", options: .caseInsensitive) != nil {
            result = result.replacingOccurrences(of: #"!+"#, with: ".", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #" +([,.;:!?])"#, with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct DemoRewriter: Sendable {
    public var lexicon: DemoLexicon

    public init(lexicon: DemoLexicon = DemoLexiconLoader.load()) {
        self.lexicon = lexicon
    }

    public func rewrite(_ text: String, action: RewriteAction, tone: RewriteTone) -> String {
        rewrite(text, action: action, tone: tone, extras: .empty)
    }

    public func rewrite(_ text: String, action: RewriteAction, tone: RewriteTone, extras: DemoRewriteExtras) -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return source }
        var output: String = switch action {
        case .correct:
            correct(source)
        case .improve:
            improve(correct(source))
        case .rewrite:
            rewriteNatural(improve(correct(source)))
        case .shorten:
            shorten(correct(source))
        case .changeTone:
            applyTone(correct(source), tone)
        case .expand:
            expand(correct(source))
        case .simplify:
            simplify(correct(source))
        case .bullets:
            bullets(correct(source))
        case .continueWriting:
            continueWriting(correct(source))
        }
        output = applyPreset(output, extras.preset)
        output = applyLength(output, extras.length)
        output = StyleRules.applyCustomInstructions(output, extras.customInstructions)
        return action == .bullets ? tidy(output) : capitalizeSentences(tidy(output))
    }

    public func applyPreset(_ text: String, _ preset: WritingPreset?) -> String {
        guard let preset else { return text }
        let name = preset.name.lowercased()
        let prompt = preset.systemPrompt.lowercased()
        if name == "concise" || prompt.contains("short sentences") || prompt.contains("cut anything") {
            return shorten(text)
        }
        if name == "professional" || prompt.contains("professional tone") {
            return applyTone(text, .professional)
        }
        if name == "casual" || prompt.contains("relaxed") {
            return applyTone(text, .casual)
        }
        if name == "warm" || prompt.contains("warmth") {
            return applyTone(text, .friendly)
        }
        return text
    }

    public func applyLength(_ text: String, _ length: RewriteLength) -> String {
        switch length {
        case .shorter: shorten(text)
        case .longer: expand(text)
        case .same: text
        }
    }

    public func correct(_ text: String) -> String {
        var result = replaceMapped(text, lexicon.typos)
        result = replaceMapped(result, lexicon.casualSlang)
        result = normalizeSpaces(result)
        result = fixStandaloneI(result)
        if let regex = try? NSRegularExpression(pattern: "\\b(brief|document|note|draft) need\\b", options: [.caseInsensitive]) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let wordRange = Range(match.range(at: 1), in: result) else { continue }
                result.replaceSubrange(range, with: "\(result[wordRange]) needs")
            }
        }
        return capitalizeSentences(result)
    }

    public func improve(_ text: String) -> String {
        var result = removeListedPhrases(text, lexicon.filler)
        result = replaceMapped(result, lexicon.wordy)
        return normalizeSpaces(result)
    }

    public func shorten(_ text: String) -> String {
        var result = improve(text)
        result = result.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        result = dropTrailingSoftener(result)
        return normalizeSpaces(result)
    }

    public func applyTone(_ text: String, _ tone: RewriteTone) -> String {
        switch tone {
        case .professional:
            var result = replaceMapped(text, lexicon.casualSlang)
            result = replaceMapped(result, lexicon.expandContractions)
            return capitalizeSentences(result)
        case .casual:
            return replaceMapped(text, lexicon.addContractions)
        case .friendly:
            var result = replaceMapped(text, lexicon.addContractions)
            result = removeListedPhrases(result, ["unfortunately", "regrettably"])
            return result
        case .confident:
            var result = removeListedPhrases(text, lexicon.hedges)
            result = removeListedPhrases(result, lexicon.filler)
            return normalizeSpaces(result)
        }
    }

    public func expand(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains("That is the point to keep in view.") {
            return cleaned
        }
        let addition = "That is the point to keep in view."
        if cleaned.hasSuffix(".") || cleaned.hasSuffix("!") || cleaned.hasSuffix("?") {
            return cleaned + " " + addition
        }
        return cleaned + ". " + addition
    }

    public func simplify(_ text: String) -> String {
        replaceMapped(text, lexicon.simplify)
    }

    public func bullets(_ text: String) -> String {
        let sentences = splitSentences(text)
        if sentences.count >= 2 {
            return sentences.map { "- \($0)" }.joined(separator: "\n")
        }
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return parts.map { "- \(trimListPunctuation($0))" }.joined(separator: "\n")
        }
        return "- \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public func continueWriting(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = splitSentences(cleaned).last ?? cleaned
        if last.hasSuffix("?") {
            return cleaned + " The short answer is yes, for the reasons already stated."
        }
        let snippet = last.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        let clipped = snippet.split(separator: " ").suffix(6).joined(separator: " ")
        if clipped.isEmpty {
            return cleaned + " The next step is to act on that."
        }
        return cleaned + " The next step is to follow through on \(clipped.prefix(1).lowercased() + clipped.dropFirst())."
    }

    public func rewriteNatural(_ text: String) -> String {
        let sentences = splitSentences(text)
        guard sentences.count >= 2 else {
            return text.hasSuffix(".") ? text : text + "."
        }
        let first = sentences[0]
        let rest = Array(sentences.dropFirst())
        return (rest + [first]).joined(separator: " ")
    }

    private func replaceMapped(_ text: String, _ map: [String: String]) -> String {
        var result = text
        for (key, value) in map.sorted(by: { $0.key.count > $1.key.count }) {
            result = replacePhrase(result, key, value)
        }
        return result
    }

    private func removeListedPhrases(_ text: String, _ phrases: [String]) -> String {
        var result = text
        for phrase in phrases.sorted(by: { $0.count > $1.count }) {
            result = replacePhrase(result, phrase, "")
        }
        return normalizeSpaces(result)
    }

    private func replacePhrase(_ text: String, _ key: String, _ value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var output = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let sample = String(output[range])
            let replacement = value.isEmpty ? "" : preserveCase(sample: sample, replacement: value)
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    private func preserveCase(sample: String, replacement: String) -> String {
        if sample.count > 1 && sample == sample.uppercased() {
            return replacement.uppercased()
        }
        if let first = sample.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private func normalizeSpaces(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #" *\n+ *"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #" +([,.;:!?])"#, with: "$1", options: .regularExpression)
        result = insertSentenceBreaks(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inserts a space after sentence-final punctuation directly followed by a
    /// letter ("word.Next" -> "word. Next") while protecting common abbreviations
    /// ("e.g.", "i.e.", "Dr.", "U.S."), domain-like tokens ("example.com") and
    /// decimal or version numbers ("3.5", "v1.2a").
    private func insertSentenceBreaks(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(text.count)
        for (index, character) in characters.enumerated() {
            if character.isLetter, index > 0 {
                let previous = characters[index - 1]
                if previous == "." {
                    if !isProtectedPeriod(in: characters, at: index - 1, beforeLetterAt: index) {
                        result.append(" ")
                    }
                } else if previous == "!" || previous == "?" {
                    result.append(" ")
                }
            }
            result.append(character)
        }
        return result
    }

    private func isProtectedPeriod(in characters: [Character], at periodIndex: Int, beforeLetterAt letterIndex: Int) -> Bool {
        let previous = periodIndex > 0 ? characters[periodIndex - 1] : nil
        let next = characters[letterIndex]
        // Decimal or version number: "3.5", "v1.2a".
        if previous?.isNumber == true, next.isNumber {
            return true
        }
        // Domain-like token: a lowercase dotted token whose final label is a
        // short TLD-style suffix ("example.com", "files.archive.org").
        if let previous, previous.isLetter, periodIndex >= 2 {
            let parts = dottedToken(in: characters, containing: periodIndex)
            let isDomainLike = parts.count >= 2
                && parts.allSatisfy { !$0.isEmpty && $0 == $0.lowercased() }
                && (parts.last?.count ?? 0) <= 4
            if isDomainLike {
                return true
            }
        }
        // Common abbreviations such as "e.g.", "i.e.", "etc.", "vs.", "Dr.", "U.S.".
        if isAbbreviationPeriod(in: characters, at: periodIndex, followedBy: next) {
            return true
        }
        return false
    }

    /// Splits the surrounding word at periods: "files.archive.org" -> ["files", "archive", "org"].
    private func dottedToken(in characters: [Character], containing periodIndex: Int) -> [String] {
        var start = periodIndex
        while start > 0, characters[start - 1].isLetter || characters[start - 1] == "." {
            start -= 1
        }
        var end = periodIndex + 1
        while end < characters.count, characters[end].isLetter || characters[end] == "." {
            end += 1
        }
        return String(characters[start..<end])
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func isAbbreviationPeriod(in characters: [Character], at periodIndex: Int, followedBy next: Character) -> Bool {
        // Multi-part initialisms: "e.g.", "i.e.", "U.S." - a letter, period,
        // letter, period, followed by a letter or whitespace.
        if periodIndex >= 2,
           characters[periodIndex - 1].isLetter,
           characters[periodIndex - 2] == ".",
           periodIndex >= 3, characters[periodIndex - 3].isLetter {
            return true
        }
        // The trailing period of an initialism is still protected when the next
        // sentence begins: "…e.g. This continues."
        if next.isWhitespace, periodIndex >= 2,
           characters[periodIndex - 1].isLetter,
           characters[periodIndex - 2] == "." {
            return true
        }
        // Word abbreviations such as "etc.", "vs.", "Dr.", "Mr.", "Mrs.".
        var start = periodIndex
        while start > 0, characters[start - 1].isLetter {
            start -= 1
        }
        guard start < periodIndex else { return false }
        let stem = String(characters[start..<periodIndex]).lowercased()
        guard Self.wordAbbreviations.contains(stem) else { return false }
        // "etc. Next" ends a sentence; "etc. next" continues it. Single-letter
        // stems ("a.m.") and lowercase continuations are never sentence breaks.
        if stem.count == 1 { return true }
        return next.isLowercase
    }

    private static let wordAbbreviations: Set<String> = [
        "e", "i", "g", "u", "s", // components of e.g. / i.e. / U.S.
        "etc", "vs", "dr", "mr", "mrs", "ms", "st", "jr", "sr", "prof", "inc", "ltd", "no", "approx", "dept", "est"
    ]

    private func fixStandaloneI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\bi\\b") else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "I")
    }

    private func capitalizeSentences(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        var capitalize = true
        for (index, character) in characters.enumerated() {
            if capitalize, character.isLetter {
                result.append(String(character).uppercased())
                capitalize = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    capitalize = isSentenceFinalPunctuation(in: characters, at: index)
                }
            }
        }
        return result
    }

    /// Punctuation only ends a sentence when it is at the end of the text or is
    /// followed by whitespace, and is not part of a number ("version 3.5 is")
    /// or an abbreviation ("e.g.", "Dr.").
    private func isSentenceFinalPunctuation(in characters: [Character], at index: Int) -> Bool {
        let character = characters[index]
        if character == "." {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if let previous, previous.isNumber, let next, next.isNumber { return false }
            if let previous, previous.isLetter, isAbbreviationPeriod(in: characters, at: index, followedBy: next ?? " ") {
                return false
            }
        }
        guard index + 1 < characters.count else { return true }
        return characters[index + 1].isWhitespace
    }

    private func splitSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[.!?])\s+"#
        return text
            .components(separatedBy: RegexWrapper(pattern))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func trimListPunctuation(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".") || value.hasSuffix(";") {
            value.removeLast()
        }
        return capitalizeSentences(value)
    }

    private func dropTrailingSoftener(_ text: String) -> String {
        let softeners = [", I guess", ", I suppose", ", you know", " I guess", " I suppose"]
        var result = text
        for ending in softeners {
            if result.lowercased().hasSuffix(ending.lowercased()) {
                result.removeLast(ending.count)
            }
        }
        return result
    }

    private func tidy(_ text: String) -> String {
        normalizeSpaces(text)
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
    }
}

private struct RegexWrapper {
    let pattern: String
    init(_ pattern: String) { self.pattern = pattern }
}

private extension String {
    func components(separatedBy wrapper: RegexWrapper) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: wrapper.pattern) else { return [self] }
        let ns = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: ns.length))
        var last = 0
        var parts: [String] = []
        for match in matches {
            let range = NSRange(location: last, length: match.range.location - last)
            parts.append(ns.substring(with: range))
            last = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: last))
        return parts
    }
}

public struct DemoClient: LLMClient {
    public var rewriter: DemoRewriter
    public var streamDelayNanoseconds: UInt64
    public var length: RewriteLength
    public var customInstructions: String

    public init(
        rewriter: DemoRewriter = DemoRewriter(),
        streamDelayNanoseconds: UInt64 = 8_000_000,
        length: RewriteLength = .same,
        customInstructions: String = ""
    ) {
        self.rewriter = rewriter
        self.streamDelayNanoseconds = streamDelayNanoseconds
        self.length = length
        self.customInstructions = customInstructions
    }

    public func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult {
        try SelectionValidator.validate(text)
        let extras = DemoRewriteExtras(length: length, preset: preset, customInstructions: customInstructions)
        let output = rewriter.rewrite(text, action: action, tone: tone, extras: extras)
        guard !output.isEmpty else { throw TajpoError.emptyResponse }
        var partial = ""
        for character in output {
            try Task.checkCancellation()
            partial.append(character)
            await onPartial(partial)
            if streamDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: streamDelayNanoseconds)
            }
        }
        return RewriteResult(
            text: output,
            usage: TokenUsage(promptTokens: text.split(separator: " ").count, completionTokens: output.split(separator: " ").count)
        )
    }

    public func ping() async throws {}
}
