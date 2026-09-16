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
        if let url = Bundle.module.url(forResource: "demo-lexicon", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let lexicon = try? JSONDecoder().decode(DemoLexicon.self, from: data) {
            return lexicon
        }
        return DemoLexicon(
            typos: ["teh": "the", "dont": "don't", "im": "I'm"],
            filler: ["just", "really", "very", "actually"],
            hedges: ["I think", "maybe", "perhaps"],
            wordy: ["in order to": "to", "due to the fact that": "because"],
            simplify: ["utilize": "use", "commence": "start"],
            expandContractions: ["don't": "do not", "I'm": "I am"],
            addContractions: ["do not": "don't", "I am": "I'm"],
            casualSlang: ["gonna": "going to"]
        )
    }
}

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
        result = result.replacingOccurrences(of: #"([.!?])([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fixStandaloneI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\bi\\b") else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "I")
    }

    private func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalize = true
        for character in text {
            if capitalize, character.isLetter {
                result.append(String(character).uppercased())
                capitalize = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    capitalize = true
                }
            }
        }
        return result
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
