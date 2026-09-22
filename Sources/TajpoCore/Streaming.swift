import Foundation

/// One meaningful event from a Chat Completions server-sent-event stream.
public enum StreamEvent: Equatable, Sendable {
    case delta(String)
    case finished(reason: String)
    case failure(String)
    case done
}

public enum SSEParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
            let finish_reason: String?
        }
        struct APIError: Decodable { let message: String? }
        let choices: [Choice]?
        let error: APIError?
    }

    /// Parses one line of the stream. Non-data lines and malformed JSON yield no events.
    public static func parse(line: String) -> [StreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        var payload = line.dropFirst(5)
        if payload.first == " " { payload = payload.dropFirst() }
        if payload == "[DONE]" { return [.done] }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) else { return [] }
        if let error = chunk.error {
            return [.failure(error.message ?? "Unknown error")]
        }
        var events: [StreamEvent] = []
        if let choice = chunk.choices?.first {
            if let content = choice.delta?.content, !content.isEmpty {
                events.append(.delta(content))
            }
            if let reason = choice.finish_reason {
                events.append(.finished(reason: reason))
            }
        }
        return events
    }
}

/// Collects stream events and decides whether the result is complete.
public struct StreamAccumulator: Sendable {
    public private(set) var text = ""
    public private(set) var finishReason: String?
    public private(set) var sawDone = false

    public init() {}

    /// Returns `true` when the text changed.
    @discardableResult
    public mutating func consume(_ event: StreamEvent) throws -> Bool {
        switch event {
        case .delta(let piece):
            text += piece
            return true
        case .finished(let reason):
            finishReason = reason
        case .failure(let message):
            throw TajpoError.api(message)
        case .done:
            sawDone = true
        }
        return false
    }

    public var isComplete: Bool { sawDone }

    /// The final text, or an error if the output is unusable for replacement.
    public func result() throws -> String {
        switch finishReason {
        case "length":
            throw TajpoError.outputTruncated
        case "content_filter":
            throw TajpoError.contentFiltered
        case nil where !sawDone:
            throw TajpoError.incompleteResponse
        default:
            break
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TajpoError.emptyResponse
        }
        return text
    }
}

public enum OpenAIErrorParser {
    public struct Details: Equatable, Sendable {
        public let message: String?
        public let code: String?
        public let type: String?
    }

    public static func details(from body: String) -> Details {
        struct Body: Decodable {
            struct ErrorBody: Decodable {
                let message: String?
                let code: String?
                let type: String?
            }
            let error: ErrorBody?
        }
        guard let parsed = try? JSONDecoder().decode(Body.self, from: Data(body.utf8)), let error = parsed.error else {
            return Details(message: nil, code: nil, type: nil)
        }
        return Details(message: error.message, code: error.code, type: error.type)
    }

    public static func message(from body: String, status: Int) -> String {
        if let message = details(from: body).message, !message.isEmpty { return message }
        return "HTTP \(status)"
    }

    /// Maps a failed HTTP response to a user-facing error.
    public static func error(status: Int, body: String, retryAfter: String?) -> TajpoError {
        let details = details(from: body)
        let message = message(from: body, status: status)
        let code = details.code ?? details.type ?? ""
        switch status {
        case 401:
            return .invalidAPIKey(message)
        case 429:
            if code == "insufficient_quota" || details.type == "insufficient_quota" {
                return .insufficientQuota
            }
            return .rateLimited(retryAfterSeconds: retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        case 404:
            return .modelNotFound(message)
        case 400 where code == "model_not_found":
            return .modelNotFound(message)
        case 500...599:
            return .serverError(status)
        default:
            return .api(message)
        }
    }
}
