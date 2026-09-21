import Foundation

public struct OpenAICompatibleClient: LLMClient {
    public var endpoint: LLMEndpoint
    public var apiKey: String
    public var session: URLSession
    public var length: RewriteLength
    public var customInstructions: String
    /// Streaming liveness watchdog window: if no new bytes arrive within this
    /// many seconds, the stream is cancelled and TajpoError.streamStalled is
    /// thrown. URLSession's own (idle) timeout stays untouched.
    public var streamStallTimeout: TimeInterval

    public init(
        endpoint: LLMEndpoint,
        apiKey: String,
        session: URLSession = .shared,
        length: RewriteLength = .same,
        customInstructions: String = "",
        streamStallTimeout: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
        self.length = length
        self.customInstructions = customInstructions
        self.streamStallTimeout = streamStallTimeout
    }

    public func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult {
        try SelectionValidator.validate(text)
        var lastError: Error = TajpoError.rateLimited(retryAfter: nil)
        for attempt in 0..<RetryPolicy.maxAttempts {
            try Task.checkCancellation()
            do {
                return try await sendRewrite(text, action: action, tone: tone, preset: preset, onPartial: onPartial)
            } catch let error as TajpoError {
                lastError = error
                guard case .rateLimited(let retryAfter) = error, attempt < RetryPolicy.maxAttempts - 1 else { throw error }
                try await Task.sleep(for: .seconds(RetryPolicy.delay(forAttempt: attempt, retryAfter: retryAfter)))
            }
        }
        throw lastError
    }

    public func ping() async throws {
        try endpoint.validateTransportSecurity(apiKey: apiKey)
        var request = URLRequest(url: try endpoint.modelsURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        applyAuth(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 {
                throw TajpoError.rateLimited(retryAfter: RetryPolicy.retryAfter(from: http.value(forHTTPHeaderField: "Retry-After")))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw TajpoError.api("HTTP \(http.statusCode)")
            }
        } catch let error as TajpoError {
            throw error
        } catch {
            throw endpoint.provider == .localCompatible
                ? TajpoError.localServerUnreachable
                : TajpoError.network(error.localizedDescription)
        }
    }

    private func sendRewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult {
        try endpoint.validateTransportSecurity(apiKey: apiKey)
        var request = URLRequest(url: try endpoint.chatCompletionsURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(Request(
            model: endpoint.model,
            messages: [
                .init(role: "system", content: PromptBuilder.systemPrompt(action: action, tone: tone, preset: preset, customInstructions: customInstructions, length: length)),
                .init(role: "user", content: text)
            ],
            temperature: PromptBuilder.temperature(for: action),
            stream: true,
            streamOptions: .init(includeUsage: true)
        ))

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 {
                throw TajpoError.rateLimited(retryAfter: RetryPolicy.retryAfter(from: http.value(forHTTPHeaderField: "Retry-After")))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw TajpoError.api(try await OpenAIErrorParser.message(from: bytes, status: http.statusCode))
            }

            let accumulator = StreamAccumulator()
            let stallTimeout = streamStallTimeout
            // Race the read loop against a liveness watchdog. If no new bytes
            // arrive within the window, the watchdog throws streamStalled and
            // the group cancels the stalled read.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        accumulator.noteActivity()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                        if let message = event.error?.message, !message.isEmpty {
                            throw TajpoError.api(message)
                        }
                        if let eventUsage = event.usage {
                            accumulator.setUsage(TokenUsage(
                                promptTokens: eventUsage.promptTokens,
                                completionTokens: eventUsage.completionTokens
                            ))
                        }
                        if let parsed = RewriteFinishReason.parse(event.choices.first?.finishReason) {
                            accumulator.setFinishReason(parsed)
                        }
                        guard let delta = event.choices.first?.delta.content else { continue }
                        let combined = accumulator.append(delta)
                        await onPartial(combined)
                    }
                }
                group.addTask {
                    while true {
                        // A cancelled watchdog must exit quietly: the read loop
                        // already produced its result.
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        if accumulator.isStale(after: stallTimeout) {
                            throw TajpoError.streamStalled
                        }
                    }
                }
                do {
                    try await group.next()
                } catch {
                    group.cancelAll()
                    throw error
                }
                group.cancelAll()
            }
            let snapshot = accumulator.snapshot()
            let final = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if final.isEmpty {
                throw snapshot.finishReason == .contentFiltered ? TajpoError.emptyContentFiltered : TajpoError.emptyResponse
            }
            return RewriteResult(text: final, usage: snapshot.usage, finishReason: snapshot.finishReason)
        } catch is CancellationError {
            throw TajpoError.cancelled
        } catch let error as TajpoError {
            throw error
        } catch {
            throw endpoint.provider == .localCompatible
                ? TajpoError.localServerUnreachable
                : TajpoError.network(error.localizedDescription)
        }
    }

    private func applyAuth(to request: inout URLRequest) {
        switch endpoint.authStyle {
        case .bearer where !apiKey.isEmpty:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKeyHeader where !apiKey.isEmpty:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .none, .bearer, .apiKeyHeader:
            break
        }
    }
}

/// Lock-protected accumulator shared between the streaming read task and the
/// liveness watchdog task.
private final class StreamAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var usage: TokenUsage?
    private var finishReason: RewriteFinishReason?
    private var lastActivity = Date()

    func noteActivity() {
        lock.lock(); defer { lock.unlock() }
        lastActivity = Date()
    }

    func append(_ delta: String) -> String {
        lock.lock(); defer { lock.unlock() }
        text += delta
        lastActivity = Date()
        return text
    }

    func setUsage(_ value: TokenUsage) {
        lock.lock(); defer { lock.unlock() }
        usage = value
    }

    func setFinishReason(_ value: RewriteFinishReason) {
        lock.lock(); defer { lock.unlock() }
        finishReason = value
    }

    func isStale(after timeout: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastActivity) > timeout
    }

    func snapshot() -> (text: String, usage: TokenUsage?, finishReason: RewriteFinishReason?) {
        lock.lock(); defer { lock.unlock() }
        return (text, usage, finishReason)
    }
}

public enum OpenAIErrorParser {
    public static func message(from body: String, status: Int) -> String {
        struct APIErrorBody: Decodable {
            struct ErrorBody: Decodable { let message: String? }
            let error: ErrorBody?
        }
        if let data = body.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(APIErrorBody.self, from: data),
           let message = parsed.error?.message,
           !message.isEmpty {
            return message
        }
        return "HTTP \(status)"
    }

    public static func message(from bytes: URLSession.AsyncBytes, status: Int) async throws -> String {
        var body = ""
        for try await line in bytes.lines { body += line }
        return message(from: body, status: status)
    }
}

private struct Request: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
    let streamOptions: StreamOptions

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case streamOptions = "stream_options"
    }
}

private struct StreamOptions: Encodable {
    let includeUsage: Bool
    enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct StreamEvent: Decodable {
    let choices: [Choice]
    let error: StreamError?
    let usage: Usage?

    enum CodingKeys: String, CodingKey { case choices, error, usage }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        error = try container.decodeIfPresent(StreamError.self, forKey: .error)
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
    }

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
    }

    struct StreamError: Decodable {
        let message: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}
