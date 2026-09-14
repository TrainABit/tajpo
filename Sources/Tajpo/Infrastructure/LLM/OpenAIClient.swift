import Foundation

struct OpenAIClient: LLMClient {
    let apiKey: String
    let model: String

    func rewrite(_ text: String, action: RewriteAction, tone: RewriteTone, onPartial: @escaping @MainActor (String) -> Void) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: model, messages: [
            .init(role: "system", content: PromptBuilder.systemPrompt(action: action, tone: tone)),
            .init(role: "user", content: text)
        ], temperature: 0.3, stream: true))

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 { throw TajpoError.rateLimited }
            guard (200..<300).contains(http.statusCode) else { throw TajpoError.api("HTTP \(http.statusCode)") }

            var result = ""
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
                      let delta = event.choices.first?.delta.content else { continue }
                result += delta
                await onPartial(result)
            }
            let final = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw TajpoError.emptyResponse }
            return final
        } catch let error as TajpoError { throw error }
        catch { throw TajpoError.network(error.localizedDescription) }
    }
}

private struct Request: Encodable { let model: String; let messages: [Message]; let temperature: Double; let stream: Bool }
private struct Message: Codable { let role: String; let content: String }
private struct StreamEvent: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let delta: Delta }
    struct Delta: Decodable { let content: String? }
}
