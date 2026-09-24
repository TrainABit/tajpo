import Foundation
import Testing
@testable import Tajpo

@Suite(.serialized)
@MainActor
struct UpdateCheckerTests {
    @Test func failedRequestDoesNotAdvanceWeeklyTimestamp() async throws {
        let suite = "tajpo-update-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UpdateURLProtocol.configure(status: 503, body: "temporary failure")
        let checker = UpdateChecker(
            session: UpdateURLProtocol.makeSession(),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        await checker.check(userInitiated: false)
        #expect(defaults.double(forKey: "lastUpdateCheck") == 0)
        #expect(checker.available == nil)
    }

    @Test func validReleaseResponseIsRecordedAsACompletedCheck() async throws {
        let suite = "tajpo-update-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000)
        UpdateURLProtocol.configure(
            status: 200,
            body: #"{"tag_name":"v0.1.0","html_url":"https://github.com/TrainABit/tajpo/releases/tag/v0.1.0","draft":false,"prerelease":false}"#
        )
        let checker = UpdateChecker(
            session: UpdateURLProtocol.makeSession(),
            defaults: defaults,
            now: { now }
        )

        await checker.check(userInitiated: false)
        #expect(defaults.double(forKey: "lastUpdateCheck") == now.timeIntervalSince1970)
        #expect(checker.available == nil) // The development bundle is newer than v0.1.0.
    }
}

private final class UpdateURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Response {
        let status: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response(status: 200, body: Data())

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func configure(status: Int, body: String) {
        lock.lock()
        response = Response(status: status, body: Data(body.utf8))
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let response = Self.response
        Self.lock.unlock()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
