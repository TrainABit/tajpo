import Foundation

public enum UpdateStatus: Equatable, Sendable {
    case upToDate
    case available(version: String, url: URL)
}

public enum VersionCompare {
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        compare(normalize(remote), normalize(local)) == .orderedDescending
    }

    public static func normalize(_ raw: String) -> [Int] {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .prefix(3)
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    public static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }
}

public struct UpdateChecker: Sendable {
    public var repository: String
    public var currentVersion: String
    public var session: URLSession

    public init(repository: String, currentVersion: String = AppVersion.string, session: URLSession = .shared) {
        self.repository = repository
        self.currentVersion = currentVersion
        self.session = session
    }

    public func check() async throws -> UpdateStatus {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw TajpoError.updateCheckFailed
        }
        var request = URLRequest(url: url)
        request.setValue("Tajpo", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TajpoError.updateCheckFailed
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let page = URL(string: release.htmlURL) else { throw TajpoError.updateCheckFailed }
            if VersionCompare.isNewer(release.tagName, than: currentVersion) {
                return .available(version: release.tagName, url: page)
            }
            return .upToDate
        } catch let error as TajpoError {
            throw error
        } catch {
            throw TajpoError.updateCheckFailed
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
