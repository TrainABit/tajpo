import Foundation
import Testing
@testable import Tajpo
@testable import TajpoCore

/// URLProtocol stub used to prove that credentials are scoped to the exact
/// official OpenAI origin. The suite is serialized because the stub has one
/// deliberately small, test-only response slot.
@Suite(.serialized)
struct ProviderSafetyTests {
    @Test func customServerNeverReceivesOpenAICredentials() async throws {
        let session = StubURLProtocol.makeSession()
        defer { StubURLProtocol.clear() }
        StubURLProtocol.configure(body: Self.sse("Custom result"))

        let client = OpenAIClient(
            apiKey: "sk-do-not-forward",
            baseURL: URL(string: "https://custom.example/v1")!,
            projectID: "project-do-not-forward",
            session: session
        )
        let prompt = PromptBuilder.request(
            text: "hello",
            action: .improve,
            tone: .casual,
            preset: nil,
            model: "local-model",
            tag: "text_test"
        )
        let result = try await client.stream(prompt, model: "local-model") { _ in }
        #expect(result == "Custom result")
        let request = try #require(StubURLProtocol.lastRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == nil)
    }

    @Test func officialOpenAIReceivesOnlyItsCredential() async throws {
        let session = StubURLProtocol.makeSession()
        defer { StubURLProtocol.clear() }
        StubURLProtocol.configure(body: Self.sse("OpenAI result"))

        let client = OpenAIClient(
            apiKey: "sk-test-only",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            projectID: "project-test-only",
            session: session
        )
        let prompt = PromptBuilder.request(
            text: "hello",
            action: .improve,
            tone: .casual,
            preset: nil,
            model: "gpt-4.1-mini",
            tag: "text_test"
        )
        _ = try await client.stream(prompt, model: "gpt-4.1-mini") { _ in }
        let request = try #require(StubURLProtocol.lastRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-only")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Project") == "project-test-only")
    }

    private static func sse(_ result: String) -> String {
        let encoded = result.replacingOccurrences(of: "\"", with: "\\\"")
        return "data: {\"choices\":[{\"delta\":{\"content\":\"\(encoded)\"},\"finish_reason\":null}]}\n\n"
            + "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
            + "data: [DONE]\n\n"
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Response {
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response: Response?
    nonisolated(unsafe) private static var request: URLRequest?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func configure(body: String) {
        lock.lock()
        response = Response(body: Data(body.utf8))
        request = nil
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        response = nil
        request = nil
        lock.unlock()
    }

    static func lastRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.request = request
        let response = Self.response
        Self.lock.unlock()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if let response { client?.urlProtocol(self, didLoad: response.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
