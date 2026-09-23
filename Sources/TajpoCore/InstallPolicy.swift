import Foundation

/// Path and signing rules shared by the install handoff and its tests.
///
/// The app never writes to an install destination itself. Keeping the path
/// decision here makes it possible to test the security boundary without
/// touching the user's Applications folder.
public enum InstallPathPolicy {
    public static let bundleName = "Tajpo.app"

    public static func isTemporaryBundlePath(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized.hasPrefix("/Volumes/") || normalized.contains("/AppTranslocation/")
    }

    public static func installDestination(applicationsDirectory: String = "/Applications") -> URL {
        URL(fileURLWithPath: applicationsDirectory, isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)
    }

    public static func isAllowedInstallDestination(
        _ path: String,
        applicationsDirectory: String = "/Applications"
    ) -> Bool {
        let candidate = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let allowed = installDestination(applicationsDirectory: applicationsDirectory).standardizedFileURL
        return candidate.path == allowed.path
    }
}

/// The non-secret identity facts needed before replacing an installed app.
public struct InstallSignature: Equatable, Sendable {
    public let bundleIdentifier: String
    public let teamIdentifier: String?
    public let authority: String?

    public init(bundleIdentifier: String, teamIdentifier: String?, authority: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.authority = authority
    }
}

/// Pure replacement policy for locally verified app bundles.
///
/// A fresh ad-hoc build may be installed when there is no existing app, but
/// it cannot silently replace a team-signed installation. A signed build must
/// have the expected bundle and, when one is supplied, team identifier.
public enum InstallSignaturePolicy {
    public static func canReplace(
        replacement: InstallSignature,
        expectedBundleIdentifier: String,
        expectedTeamIdentifier: String? = nil,
        existing: InstallSignature? = nil
    ) -> Bool {
        guard replacement.bundleIdentifier == expectedBundleIdentifier,
              !replacement.bundleIdentifier.isEmpty else { return false }

        let replacementTeam = normalizedTeam(replacement.teamIdentifier)
        if let expectedTeamIdentifier {
            let expectedTeam = normalizedTeam(expectedTeamIdentifier)
            guard !expectedTeam.isEmpty, replacementTeam == expectedTeam else { return false }
        }
        guard signatureIsValid(replacement) else { return false }

        guard let existing else { return true }
        let existingTeam = normalizedTeam(existing.teamIdentifier)
        guard existing.bundleIdentifier == expectedBundleIdentifier,
              existingTeam == replacementTeam else { return false }
        return signatureIsValid(existing)
    }

    private static func signatureIsValid(_ signature: InstallSignature) -> Bool {
        let team = normalizedTeam(signature.teamIdentifier)
        let authority = (signature.authority ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Ad-hoc signatures intentionally have no team or authority. A
        // self-signed development certificate may have an authority without
        // an Apple team ID; any signature that claims a team must also have
        // an authority.
        return team.isEmpty || !authority.isEmpty
    }

    private static func normalizedTeam(_ team: String?) -> String {
        let value = (team ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "not set" ? "" : value
    }
}
