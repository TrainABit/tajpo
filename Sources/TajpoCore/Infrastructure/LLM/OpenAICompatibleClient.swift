import Foundation

public struct OpenAICompatibleClient: LLMClient {
    public var endpoint: LLMEndpoint
    public var apiKey: String
    public var session: URLSession

    public init(endpoint: LLMEndpoint, apiKey: String, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    public func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> RewriteResult {
        var lastError: Error = TajpoError.rateLimited
        for attempt in 0..<RetryPolicy.maxAttempts {
            try Task.checkCancellation()
            do {
                return try await sendRewrite(text, action: action, tone: tone, preset: preset, onPartial: onPartial)
            } catch let error as TajpoError {
                lastError = error
                guard case .rateLimited = error, attempt < RetryPolicy.maxAttempts - 1 else { throw error }
                try await Task.sleep(for: .seconds(RetryPolicy.delay(forAttempt: attempt, retryAfter: nil)))
            }
        }
        throw lastError
    }

    public func ping() async throws {
        var request = URLRequest(url: try endpoint.modelsURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        applyAuth(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 { throw TajpoError.rateLimited }
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
        var request = URLRequest(url: try endpoint.chatCompletionsURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(Request(
            model: endpoint.model,
            messages: [
                .init(role: "system", content: PromptBuilder.systemPrompt(action: action, tone: tone, preset: preset)),
                .init(role: "user", content: text)
            ],
            temperature: PromptBuilder.temperature(for: action),
            stream: true,
            streamOptions: .init(includeUsage: true)
        ))

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 { throw TajpoError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw TajpoError.api(try await OpenAIErrorParser.message(from: bytes, status: http.statusCode))
            }

            var result = ""
            var usage: TokenUsage?
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                if let message = event.error?.message, !message.isEmpty {
                    throw TajpoError.api(message)
                }
                if let eventUsage = event.usage {
                    usage = TokenUsage(
                        promptTokens: eventUsage.promptTokens ?? 0,
                        completionTokens: eventUsage.completionTokens ?? 0
                    )
                }
                guard let delta = event.choices.first?.delta.content else { continue }
                result += delta
                await onPartial(result)
            }
            let final = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw TajpoError.emptyResponse }
            return RewriteResult(text: final, usage: usage)
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
