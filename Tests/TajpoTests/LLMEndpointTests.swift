import Foundation
import Testing
@testable import TajpoCore

@Test func openAIErrorParserReadsMessage() {
    let body = #"{"error":{"message":"Incorrect API key provided"}}"#
    #expect(OpenAIErrorParser.message(from: body, status: 401) == "Incorrect API key provided")
}

@Test func openAIErrorParserFallsBackToStatus() {
    #expect(OpenAIErrorParser.message(from: "not-json", status: 502) == "HTTP 502")
}

@Test func chatCompletionsURLUsesBasePath() throws {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1/")
    #expect(try endpoint.chatCompletionsURL().absoluteString == "https://api.openai.com/v1/chat/completions")
}

@Test func azureURLIncludesDeploymentAndVersion() throws {
    let endpoint = LLMEndpoint(
        provider: .localCompatible,
        model: "gpt-4o-mini",
        baseURL: "https://example.openai.azure.com",
        apiVersion: "2024-10-21",
        authStyle: .apiKeyHeader
    )
    #expect(try endpoint.chatCompletionsURL().absoluteString == "https://example.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21")
}

@Test func azureModelsURLUsesOpenAIPathAndVersion() throws {
    let endpoint = LLMEndpoint(
        provider: .localCompatible,
        model: "gpt-4o-mini",
        baseURL: "https://example.openai.azure.com",
        apiVersion: "2024-10-21",
        authStyle: .apiKeyHeader
    )
    #expect(try endpoint.modelsURL().absoluteString == "https://example.openai.azure.com/openai/models?api-version=2024-10-21")
}

@Test func plainModelsURLIsUnchangedWithoutAPIVersion() throws {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1/")
    #expect(try endpoint.modelsURL().absoluteString == "https://api.openai.com/v1/models")
}

@Test func emptyBaseURLIsInvalid() {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "  ")
    #expect(throws: TajpoError.invalidEndpoint) {
        _ = try endpoint.chatCompletionsURL()
    }
}

@Test func retryPolicyPrefersRetryAfterHeader() async {
    // Seconds form is parsed and preferred over exponential backoff.
    #expect(RetryPolicy.retryAfter(from: "3") == 3)
    #expect(RetryPolicy.delay(forAttempt: 0, retryAfter: 5) == 5)
    #expect(RetryPolicy.delay(forAttempt: 2, retryAfter: nil) == 4)

    // HTTP-date form is also supported.
    let future = Date().addingTimeInterval(4)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    let headerDate = formatter.string(from: future)
    let parsed = try #require(RetryPolicy.retryAfter(from: headerDate))
    #expect(parsed > 0 && parsed <= 4)

    // The header value actually captured at the HTTP 429 site drives the retry delay.
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1")
    StubURLProtocol.requestHandler = { request in
        StubURLProtocol.respond(status: 429, headers: ["Retry-After": "0.2"], request: request)
    }
    defer { StubURLProtocol.requestHandler = nil }
    let client = OpenAICompatibleClient(endpoint: endpoint, apiKey: "sk-test", session: StubURLProtocol.makeSession())
    let started = Date()
    do {
        _ = try await client.rewrite("hello there", action: .correct, tone: .casual, preset: nil) { _ in }
        Issue.record("Expected a rate limit error")
    } catch TajpoError.rateLimited(let retryAfter) {
        // The 429 site must carry the header value through on the thrown error.
        #expect(retryAfter == 0.2)
        // maxAttempts attempts, each delayed by the Retry-After header (~0.2s each).
        #expect(Date().timeIntervalSince(started) >= 0.3)
    } catch {
        Issue.record("Expected TajpoError.rateLimited, got \(error)")
    }
}

@Test func retryPolicyRejectsGarbageRetryAfter() {
    #expect(RetryPolicy.retryAfter(from: nil) == nil)
    #expect(RetryPolicy.retryAfter(from: "") == nil)
    #expect(RetryPolicy.retryAfter(from: "soon") == nil)
    #expect(RetryPolicy.retryAfter(from: "-5") == nil)
}

@Test func tokenCostEstimatesKnownModels() {
    let usage = TokenUsage(promptTokens: 1_000_000, completionTokens: 1_000_000)
    #expect(TokenCost.estimateUSD(model: "gpt-4o-mini", usage: usage) == 0.75)
    #expect(TokenCost.estimateUSD(model: "unknown-local", usage: usage) == nil)
    #expect(TokenCost.label(model: "unknown-local", usage: TokenUsage(promptTokens: 2, completionTokens: 3)) == "5 tokens")
    // A usage event missing one field yields no cost label rather than a
    // misleading zero-filled estimate.
    #expect(TokenCost.label(model: "gpt-4o-mini", usage: TokenUsage(promptTokens: 12, completionTokens: nil)) == "")
    #expect(TokenCost.estimateUSD(model: "gpt-4o-mini", usage: TokenUsage(promptTokens: 12, completionTokens: nil)) == nil)
}

@Test func localProviderDoesNotRequireKey() {
    #expect(LLMProvider.openAI.requiresAPIKey)
    #expect(!LLMProvider.localCompatible.requiresAPIKey)
    #expect(!LLMProvider.demo.requiresAPIKey)
}
