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
    static let maximumResponseCharacters = 200_000
    static let maximumSSELineBytes = 1_000_000
    static let maximumErrorBodyBytes = 65_536

    /// Never follow an HTTP redirect with a provider request. In particular,
    /// this prevents an official OpenAI request from being replayed with its
    /// Authorization header to an unrelated host.
    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    let apiKey: String?
    let baseURL: URL
    let projectID: String?
    var session: URLSession = OpenAIClient.defaultSession

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

            var accumulator = StreamAccumulator(maximumCharacters: Self.maximumResponseCharacters)
            var lastEmit = ContinuousClock.now
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.utf8.count <= Self.maximumSSELineBytes else {
                    throw TajpoError.api("The AI server sent an oversized response line.")
                }
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
            let (bytes, response) = try await session.bytes(for: try makeRequest(body))
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            let data = try await Self.readLimitedData(from: bytes, limit: Self.maximumErrorBodyBytes)
            guard (200..<300).contains(http.statusCode) else {
                throw OpenAIErrorParser.error(
                    status: http.statusCode,
                    body: String(decoding: data, as: UTF8.self),
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                )
            }
            do {
                let payload = try JSONDecoder().decode(ConnectionResponse.self, from: data)
                guard payload.choices.contains(where: { $0.message?.content != nil || $0.delta?.content != nil }) else {
                    throw TajpoError.api("The server accepted the request but did not return a valid completion.")
                }
            } catch let error as TajpoError {
                throw error
            } catch {
                throw TajpoError.api("The server returned an invalid connection-test response.")
            }
        }
    }

    private struct ConnectionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            struct Delta: Decodable { let content: String? }
            let message: Message?
            let delta: Delta?
        }
        let choices: [Choice]
    }

    private func makeRequest(_ body: Body) throws -> URLRequest {
        let validatedBaseURL = try ProviderSettings.validateBaseURL(baseURL.absoluteString)
        var request = URLRequest(url: ProviderSettings.chatCompletionsURL(baseURL: validatedBaseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if ProviderSettings.isOfficialOpenAI(baseURL: validatedBaseURL) {
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if let projectID, !projectID.isEmpty {
                request.setValue(projectID, forHTTPHeaderField: "OpenAI-Project")
            }
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func check(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
        guard (200..<300).contains(http.statusCode) else {
            let data = try await readLimitedData(from: bytes, limit: maximumErrorBodyBytes)
            throw OpenAIErrorParser.error(
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self),
                retryAfter: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
    }

    private static func readLimitedData(
        from bytes: URLSession.AsyncBytes,
        limit: Int
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard data.count + line.utf8.count + 1 <= limit else {
                throw TajpoError.api("The AI server returned an oversized response.")
            }
            data.append(contentsOf: line.utf8)
            data.append(0x0A)
        }
        return data
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
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw TajpoError.network("macOS only allows plain http:// for literal loopback addresses (localhost, 127.0.0.1, or ::1). Use https:// or a loopback address for this server")
        } catch {
            if Task.isCancelled { throw TajpoError.cancelled }
            throw TajpoError.network(error.localizedDescription)
        }
    }
}
