import Foundation

/// A MAJOR.MINOR.PATCH version such as "0.3.0" or tag "v0.3.0".
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// The newest published release, as reported by GitHub's releases API.
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public let tag_name: String
    public let html_url: String
    public let draft: Bool?
    public let prerelease: Bool?

    public var version: AppVersion? { AppVersion(tag_name) }

    /// Whether this release is newer than `current` and meant for everyone.
    public func isUpdate(from current: String) -> Bool {
        guard draft != true, prerelease != true, let version, let installed = AppVersion(current) else { return false }
        return version > installed
    }
}
