import AppKit
import TajpoCore

/// Checks GitHub Releases for a newer version. Only runs when the user asks,
/// or weekly if they turned on automatic checks. Sends no app data; the
/// network request still has ordinary transport metadata such as an IP.
@MainActor
final class UpdateChecker: ObservableObject {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/TrainABit/tajpo/releases/latest")!
    private static let autoKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let maximumResponseBytes = 1_048_576

    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var isChecking = false

    private let session: URLSession
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.defaults = defaults
        self.now = now
    }

    var automatic: Bool {
        get { defaults.bool(forKey: Self.autoKey) }
        set {
            defaults.set(newValue, forKey: Self.autoKey)
            objectWillChange.send()
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    /// Runs a silent check at launch when automatic checks are on and a week has passed.
    func checkOnLaunchIfDue() {
        guard automatic else { return }
        let last = defaults.double(forKey: Self.lastCheckKey)
        guard now().timeIntervalSince1970 - last > 7 * 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tajpo/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    // A repository with no published release is a valid,
                    // completed state—not a reason to retry on every launch.
                    defaults.set(now().timeIntervalSince1970, forKey: Self.lastCheckKey)
                    available = nil
                } else if userInitiated {
                    alert(message(for: http.statusCode), info: "GitHub did not return release information. Try again later.")
                }
                return
            }
            guard data.count <= Self.maximumResponseBytes else { throw UpdateError.invalidResponse }
            let release: ReleaseInfo
            do {
                release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            } catch {
                throw UpdateError.invalidResponse
            }
            // Only a successfully parsed response counts as a completed check.
            defaults.set(now().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if release.isUpdate(from: Self.currentVersion) {
                available = release
                if userInitiated { offer(release) }
            } else {
                available = nil
                if userInitiated { alert("Tajpo is up to date.", info: "You have version \(Self.currentVersion).") }
            }
        } catch {
            if userInitiated { alert("Couldn't check for updates.", info: error.localizedDescription) }
        }
    }

    func openAvailable() {
        guard let available,
              let url = URL(string: available.html_url),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }

    private func message(for status: Int) -> String {
        switch status {
        case 403: "GitHub temporarily refused the update check."
        case 404: "No published release found yet."
        case 429: "GitHub is rate-limiting update checks."
        default: "The update service is unavailable (HTTP \(status))."
        }
    }

    private func offer(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Tajpo \(release.version?.description ?? release.tag_name) is available."
        alert.informativeText = "You have version \(Self.currentVersion). Download the new version from GitHub and replace Tajpo in your Applications folder. Your settings, key, and permissions carry over."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { openAvailable() }
    }

    private func alert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "GitHub returned an invalid update response." }
    }
}
