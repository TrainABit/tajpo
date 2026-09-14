import Foundation

struct OpenAIClient: LLMClient {
    let apiKey: String
    let model: String

    func rewrite(_ text: String, action: RewriteAction, tone: RewriteTone) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: model, messages: [
            .init(role: "system", content: systemPrompt(action: action, tone: tone)),
            .init(role: "user", content: text)
        ], temperature: 0.3))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 { throw TajpoError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? JSONDecoder().decode(APIError.self, from: data).error.message) ?? "HTTP \(http.statusCode)"
                throw TajpoError.api(detail)
            }
            let result = try JSONDecoder().decode(Response.self, from: data)
            guard let output = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { throw TajpoError.emptyResponse }
            return output
        } catch let error as TajpoError { throw error }
        catch { throw TajpoError.network(error.localizedDescription) }
    }

    private func systemPrompt(action: RewriteAction, tone: RewriteTone) -> String {
        let task: String = switch action {
        case .improve: "Improve grammar, clarity, and flow."
        case .rewrite: "Rewrite naturally while preserving the meaning."
        case .shorten: "Make it substantially shorter without losing key information."
        case .changeTone: "Rewrite it in a \(tone.rawValue) tone."
        }
        return "\(task) Preserve the original language unless asked otherwise. Do not add facts. Return only the final text, without quotes or commentary."
    }
}

private struct Request: Encodable { let model: String; let messages: [Message]; let temperature: Double }
private struct Message: Codable { let role: String; let content: String }
private struct Response: Decodable { let choices: [Choice]; struct Choice: Decodable { let message: Message } }
private struct APIError: Decodable { let error: Detail; struct Detail: Decodable { let message: String } }
