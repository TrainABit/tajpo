import Foundation
import TajpoCore

protocol LLMClient: Sendable {
    /// Streams a completion. `onPartial` receives the accumulated text, at most ~20 times a second.
    func stream(_ prompt: PromptRequest, model: String, onPartial: @escaping @MainActor (String) -> Void) async throws -> String
    /// Sends a tiny request to check the key, credit, and model.
    func testConnection(model: String) async throws
}

/// OpenAI Chat Completions, or any OpenAI-compatible server (Ollama, LM Studio, llama.cpp).
struct OpenAIClient: LLMClient {
    let apiKey: String?
    let baseURL: URL
    let projectID: String?
    var session: URLSession = .shared

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Body: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        let stream: Bool
        let max_completion_tokens: Int?
        let max_tokens: Int?
    }

    private var isOpenAI: Bool { ProviderSettings.requiresAPIKey(baseURL: baseURL) }

    func stream(_ prompt: PromptRequest, model: String, onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        let body = Body(
            model: model,
            messages: [.init(role: "system", content: prompt.system), .init(role: "user", content: prompt.user)],
            temperature: prompt.temperature,
            stream: true,
            max_completion_tokens: nil,
            max_tokens: nil
        )
        return try await mapErrors {
            let (bytes, response) = try await session.bytes(for: try makeRequest(body))
            try await Self.check(response, bytes: bytes)

            var accumulator = StreamAccumulator()
            var lastEmit = ContinuousClock.now
            for try await line in bytes.lines {
                try Task.checkCancellation()
                var changed = false
                for event in SSEParser.parse(line: line) {
                    changed = try accumulator.consume(event) || changed
                }
                if changed, ContinuousClock.now - lastEmit > .milliseconds(50) {
                    lastEmit = ContinuousClock.now
                    await onPartial(accumulator.text)
                }
                if accumulator.isComplete { break }
            }
            try Task.checkCancellation()
            await onPartial(accumulator.text)
            return try accumulator.result()
        }
    }

    func testConnection(model: String) async throws {
        let body = Body(
            model: model,
            messages: [.init(role: "user", content: "Reply with OK.")],
            temperature: nil,
            stream: false,
            max_completion_tokens: isOpenAI ? 16 : nil,
            max_tokens: isOpenAI ? nil : 16
        )
        try await mapErrors {
            let (data, response) = try await session.data(for: try makeRequest(body))
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            guard (200..<300).contains(http.statusCode) else {
                throw OpenAIErrorParser.error(
                    status: http.statusCode,
                    body: String(decoding: data.prefix(65_536), as: UTF8.self),
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                )
            }
        }
    }

    private func makeRequest(_ body: Body) throws -> URLRequest {
        var request = URLRequest(url: ProviderSettings.chatCompletionsURL(baseURL: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let projectID, !projectID.isEmpty {
            request.setValue(projectID, forHTTPHeaderField: "OpenAI-Project")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func check(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line + "\n"
                if body.utf8.count > 65_536 { break }
            }
            throw OpenAIErrorParser.error(status: http.statusCode, body: body, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
    }

    /// Normalizes errors: URLSession reports cancellation as `URLError(.cancelled)`.
    private func mapErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as TajpoError {
            throw error
        } catch is CancellationError {
            throw TajpoError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw TajpoError.cancelled
        } catch {
            if Task.isCancelled { throw TajpoError.cancelled }
            throw TajpoError.network(error.localizedDescription)
        }
    }
}
