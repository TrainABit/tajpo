import AppKit
import TajpoCore

/// Checks GitHub Releases for a newer version. Only runs when the user asks,
/// or weekly if they turned on automatic checks. Sends no personal data.
@MainActor
final class UpdateChecker: ObservableObject {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/TrainABit/tajpo/releases/latest")!
    private static let autoKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"

    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var isChecking = false

    var automatic: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoKey)
            objectWillChange.send()
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    /// Runs a silent check at launch when automatic checks are on and a week has passed.
    func checkOnLaunchIfDue() {
        guard automatic else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 7 * 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                if userInitiated { alert("No published release found yet.", info: "Check again later.") }
                return
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
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
        if let available, let url = URL(string: available.html_url) { NSWorkspace.shared.open(url) }
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
}
