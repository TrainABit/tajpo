import Foundation

public enum UpdateStatus: Equatable, Sendable {
    case upToDate
    case available(version: String, url: URL)
}

public enum VersionCompare {
    /// A parsed semantic version: numeric core plus optional prerelease
    /// identifiers. Build metadata (+...) is ignored for precedence.
    public struct Semver: Equatable, Sendable {
        public var core: [Int]
        public var prerelease: [String]

        public init(core: [Int], prerelease: [String] = []) {
            self.core = core
            self.prerelease = prerelease
        }
    }

    /// Parses a tag into a Semver, or nil when it is malformed. Accepts an
    /// optional "v" prefix and 1–3 numeric core components. Anything that does
    /// not match is rejected rather than guessed at.
    public static func parse(_ raw: String) -> Semver? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let plus = text.firstIndex(of: "+") { text = String(text[text.startIndex..<plus]) }
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let corePart = parts.first else { return nil }
        let coreFields = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(coreFields.count) else { return nil }
        var core: [Int] = []
        for field in coreFields {
            guard !field.isEmpty, field.allSatisfy(\.isNumber), let value = Int(field) else { return nil }
            core.append(value)
        }
        var prerelease: [String] = []
        if parts.count == 2 {
            let pre = parts[1]
            guard !pre.isEmpty else { return nil }
            let identifiers = pre.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            for identifier in identifiers {
                guard !identifier.isEmpty else { return nil }
                guard identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
                prerelease.append(identifier)
            }
        }
        return Semver(core: core, prerelease: prerelease)
    }

    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let remoteVersion = parse(remote), let localVersion = parse(local) else { return false }
        return compare(remoteVersion, localVersion) == .orderedDescending
    }

    /// Numeric core only — kept for callers that want the raw components.
    public static func normalize(_ raw: String) -> [Int] {
        parse(raw)?.core ?? []
    }

    public static func compare(_ remote: Semver, _ local: Semver) -> ComparisonResult {
        let count = max(remote.core.count, local.core.count)
        for index in 0..<count {
            let left = index < remote.core.count ? remote.core[index] : 0
            let right = index < local.core.count ? local.core[index] : 0
            if left != right { return left > right ? .orderedDescending : .orderedAscending }
        }
        // Same core: a release outranks its prerelease.
        switch (remote.prerelease.isEmpty, local.prerelease.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }
        return comparePrerelease(remote.prerelease, local.prerelease)
    }

    /// Semver prerelease ordering: numeric identifiers compare numerically and
    /// sort before alphanumeric ones; a shorter set that is a prefix of a
    /// longer set sorts first.
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        let count = min(lhs.count, rhs.count)
        for index in 0..<count {
            let left = lhs[index]
            let right = rhs[index]
            if left == right { continue }
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (l?, r?):
                if l != r { return l > r ? .orderedDescending : .orderedAscending }
            case (_?, nil):
                return .orderedAscending
            case (nil, _?):
                return .orderedDescending
            case (nil, nil):
                return left > right ? .orderedDescending : .orderedAscending
            }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count > rhs.count ? .orderedDescending : .orderedAscending
    }

    public static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        compare(Semver(core: lhs), Semver(core: rhs))
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
        // Validate the repository as an owner/name pair before building a URL.
        guard Self.isValidRepository(repository) else { throw TajpoError.releaseSourceUnavailable }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw TajpoError.updateCheckFailed
        }
        var request = URLRequest(url: url)
        request.setValue("Tajpo", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TajpoError.updateCheckFailed }
            if http.statusCode == 404 {
                // Private (unauthenticated), missing, or no releases published.
                throw TajpoError.releaseSourceUnavailable
            }
            guard (200..<300).contains(http.statusCode) else {
                throw TajpoError.updateCheckFailed
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let page = validatedReleaseURL(release.htmlURL) else { throw TajpoError.updateCheckFailed }
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

    /// Owner/name pair, e.g. "TrainABit/tajpo".
    static func isValidRepository(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9-_.]*/[A-Za-z0-9][A-Za-z0-9-_.]*$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Only expose the release page to the UI when it is an HTTPS link on
    /// github.com (or api.github.com) pointing at the configured repository.
    /// A spoofed release payload can otherwise send the user to an attacker URL.
    func validatedReleaseURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "github.com" || host == "api.github.com" else { return nil }
        let expectedPath = "/\(repository)/releases"
        guard url.path.lowercased().hasPrefix(expectedPath.lowercased()) else { return nil }
        return url
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
