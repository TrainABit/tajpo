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

@Test func emptyBaseURLIsInvalid() {
    let endpoint = LLMEndpoint(provider: .openAI, model: "gpt-4o-mini", baseURL: "  ")
    #expect(throws: TajpoError.invalidEndpoint) {
        _ = try endpoint.chatCompletionsURL()
    }
}

@Test func retryPolicyPrefersRetryAfterHeader() {
    #expect(RetryPolicy.retryAfter(from: "3") == 3)
    #expect(RetryPolicy.delay(forAttempt: 0, retryAfter: 5) == 5)
    #expect(RetryPolicy.delay(forAttempt: 2, retryAfter: nil) == 4)
}

@Test func tokenCostEstimatesKnownModels() {
    let usage = TokenUsage(promptTokens: 1_000_000, completionTokens: 1_000_000)
    #expect(TokenCost.estimateUSD(model: "gpt-4o-mini", usage: usage) == 0.75)
    #expect(TokenCost.estimateUSD(model: "unknown-local", usage: usage) == nil)
    #expect(TokenCost.label(model: "unknown-local", usage: TokenUsage(promptTokens: 2, completionTokens: 3)) == "5 tokens")
}

@Test func localProviderDoesNotRequireKey() {
    #expect(LLMProvider.openAI.requiresAPIKey)
    #expect(!LLMProvider.localCompatible.requiresAPIKey)
    #expect(!LLMProvider.demo.requiresAPIKey)
}
