import Foundation

struct OpenAIClient: LLMClient {
    let apiKey: String
    let model: String

    func rewrite(
        _ text: String,
        action: RewriteAction,
        tone: RewriteTone,
        preset: WritingPreset?,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(
            model: model,
            messages: [
                .init(role: "system", content: PromptBuilder.systemPrompt(action: action, tone: tone, preset: preset)),
                .init(role: "user", content: text)
            ],
            temperature: PromptBuilder.temperature(for: action),
            stream: true
        ))

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.network("Invalid response.") }
            if http.statusCode == 429 { throw TajpoError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw TajpoError.api(try await OpenAIErrorParser.message(from: bytes, status: http.statusCode))
            }

            var result = ""
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
                guard let delta = event.choices.first?.delta.content else { continue }
                result += delta
                await onPartial(result)
            }
            let final = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw TajpoError.emptyResponse }
            return final
        } catch is CancellationError {
            throw TajpoError.cancelled
        } catch let error as TajpoError {
            throw error
        } catch {
            throw TajpoError.network(error.localizedDescription)
        }
    }

}

enum OpenAIErrorParser {
    static func message(from body: String, status: Int) -> String {
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

    static func message(from bytes: URLSession.AsyncBytes, status: Int) async throws -> String {
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
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct StreamEvent: Decodable {
    let choices: [Choice]
    let error: StreamError?

    enum CodingKeys: String, CodingKey { case choices, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        error = try container.decodeIfPresent(StreamError.self, forKey: .error)
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
}
