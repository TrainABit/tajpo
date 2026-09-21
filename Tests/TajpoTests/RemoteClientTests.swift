import Foundation
import Testing
@testable import TajpoCore

@Test func nonHTTPSEndpointWithKeyThrowsInsecureEndpoint() async {
    let endpoint = LLMEndpoint(
        provider: .openAI,
        model: "gpt-4o-mini",
        baseURL: "http://api.evil.example/v1",
        authStyle: .bearer
    )
    let client = OpenAICompatibleClient(endpoint: endpoint, apiKey: "sk-test", session: StubURLProtocol.makeSession())
    await #expect(throws: TajpoError.insecureEndpoint) {
        _ = try await client.rewrite("hello there", action: .correct, tone: .casual, preset: nil) { _ in }
    }
    await #expect(throws: TajpoError.insecureEndpoint) {
        try await client.ping()
    }
}

@Test func loopbackHTTPAllowsAPIKey() async {
    let endpoint = LLMEndpoint(
        provider: .localCompatible,
        model: "llama3.2",
        baseURL: "http://127.0.0.1:11434/v1",
        authStyle: .bearer
    )
    let body = """
    data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}]}

    data: [DONE]

    """
    StubURLProtocol.requestHandler = { request in
        // The key may be attached for a loopback server.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-local")
        return StubURLProtocol.respond(status: 200, body: body, request: request)
    }
    defer { StubURLProtocol.requestHandler = nil }
    let client = OpenAICompatibleClient(endpoint: endpoint, apiKey: "sk-local", session: StubURLProtocol.makeSession())
    let result = try await client.rewrite("hello there", action: .correct, tone: .casual, preset: nil) { _ in }
    #expect(result.text == "hi")
}

@Test func httpsEndpointWithKeyPassesTransportCheck() throws {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1")
    try endpoint.validateTransportSecurity(apiKey: "sk-test")
    // No key or no auth means nothing can leak, so any scheme is tolerated.
    try LLMEndpoint(provider: .localCompatible, model: "llama3.2", baseURL: "http://192.168.1.5:8080/v1", authStyle: .none)
        .validateTransportSecurity(apiKey: "")
}

@Test func remoteRewriteValidatesSelectionBeforeNetwork() async {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1")
    let client = OpenAICompatibleClient(endpoint: endpoint, apiKey: "sk-test", session: StubURLProtocol.makeSession())
    await #expect(throws: TajpoError.textTooLarge) {
        _ = try await client.rewrite(
            String(repeating: "a", count: SelectionValidator.maximumCharacters + 1),
            action: .correct,
            tone: .casual,
            preset: nil
        ) { _ in }
    }
}

@Test func truncatedFinishReasonIsSurfaced() async throws {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1")
    let body = """
    data: {"choices":[{"delta":{"content":"partial text"},"finish_reason":"length"}]}

    data: {"choices":[{"delta":{},"finish_reason":"length"}],"usage":{"prompt_tokens":5,"completion_tokens":2}}

    data: [DONE]

    """
    StubURLProtocol.requestHandler = { request in
        StubURLProtocol.respond(status: 200, body: body, request: request)
    }
    defer { StubURLProtocol.requestHandler = nil }
    let client = OpenAICompatibleClient(endpoint: endpoint, apiKey: "sk-test", session: StubURLProtocol.makeSession())
    let result = try await client.rewrite("hello there", action: .correct, tone: .casual, preset: nil) { _ in }
    #expect(result.text == "partial text")
    #expect(result.finishReason == .truncated)
    #expect(result.usage == TokenUsage(promptTokens: 5, completionTokens: 2))
}

@Test func emptyContentFilteredResponseIsDistinct() async {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1")
    let body = """
    data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}

    data: [DONE]

    """
    StubURLProtocol.requestHandler = { request in
        StubURLProtocol.respond(status: 200, body: body, request: request)
    }
    defer { StubURLProtocol.requestHandler = nil }
    let client = OpenAICompatibleClient(endpoint: endpoint, apiKey: "sk-test", session: StubURLProtocol.makeSession())
    await #expect(throws: TajpoError.emptyContentFiltered) {
        _ = try await client.rewrite("hello there", action: .correct, tone: .casual, preset: nil) { _ in }
    }
}
