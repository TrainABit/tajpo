import AppKit
import TajpoCore

/// Screens that can be opened directly with sample content, for screenshots
/// and visual checks: `Tajpo.app/Contents/MacOS/Tajpo -TajpoDemo panel-finished`.
/// Nothing is sent anywhere in demo mode.
enum DemoScene: String, CaseIterable {
    case onboardingWelcome = "onboarding-welcome"
    case onboardingConnect = "onboarding-connect"
    case onboardingTryIt = "onboarding-tryit"
    case onboardingEverywhere = "onboarding-everywhere"
    case onboardingDone = "onboarding-done"
    case settingsGeneral = "settings-general"
    case settingsAI = "settings-ai"
    case settingsPresets = "settings-presets"
    case settingsPrivacy = "settings-privacy"
    case panelReady = "panel-ready"
    case panelRunning = "panel-running"
    case panelFinished = "panel-finished"
    case panelCopyOnly = "panel-copyonly"
    case panelError = "panel-error"
    case panelLong = "panel-long"

    /// Shows the "not allowed yet" state even on a Mac that granted Accessibility.
    static var simulatesNoAccess: Bool {
        UserDefaults.standard.bool(forKey: "TajpoDemoNoAccess")
    }

    static var requested: DemoScene? {
        UserDefaults.standard.string(forKey: "TajpoDemo").flatMap(DemoScene.init(rawValue:))
    }
}

extension AppModel {
    static let demoOriginal = "Their going to the libary tomorow, but me and him thinks its closed. Can you check the opening hours?"
    static let demoCorrected = "They're going to the library tomorrow, but he and I think it's closed. Can you check the opening hours?"

    func showDemo(_ scene: DemoScene) {
        if UserDefaults.standard.string(forKey: "TajpoDemoAppearance") == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        switch scene {
        case .onboardingWelcome: showOnboarding(at: OnboardingStep.welcome.rawValue)
        case .onboardingConnect: showOnboarding(at: OnboardingStep.connect.rawValue)
        case .onboardingTryIt: showOnboarding(at: OnboardingStep.tryIt.rawValue)
        case .onboardingEverywhere: showOnboarding(at: OnboardingStep.everywhere.rawValue)
        case .onboardingDone: showOnboarding(at: OnboardingStep.done.rawValue)
        case .settingsGeneral: showSettings(tab: .general)
        case .settingsAI: showSettings(tab: .ai)
        case .settingsPresets: showSettings(tab: .presets)
        case .settingsPrivacy: showSettings(tab: .privacy)
        case .panelReady:
            demoPanel(text: Self.demoOriginal)
        case .panelRunning:
            demoPanel(text: Self.demoOriginal)
            session.begin(.improve)
            session.update(preview: "They're going to the library tomorrow, but he and I")
        case .panelFinished:
            demoPanel(text: Self.demoOriginal)
            session.begin(.correct)
            session.finish(Self.demoCorrected)
        case .panelCopyOnly:
            demoPanel(text: Self.demoOriginal, blocker: .replaceNotSupported)
            session.begin(.shorten)
            session.finish("They're going to the library tomorrow, but we think it's closed. Can you check the hours?")
        case .panelError:
            session.reset()
            session.fail(.noSelection)
            panel.show(model: self, near: nil, sourceName: "TextEdit", sourceIcon: Self.demoIcon)
        case .panelLong:
            let long = Array(repeating: Self.demoOriginal, count: 12).joined(separator: "\n\n")
            demoPanel(text: long)
            session.begin(.correct)
            session.finish(Array(repeating: Self.demoCorrected, count: 12).joined(separator: "\n\n"))
        }
    }

    private static var demoIcon: NSImage {
        NSWorkspace.shared.icon(forFile: "/System/Applications/TextEdit.app")
    }

    private func demoPanel(text: String, blocker: TajpoError? = nil) {
        session.reset()
        session.captured(TextCapture(text: text, method: .local, element: nil, selectedRange: nil,
                                     sourceApp: nil, bounds: nil, replaceBlocker: blocker))
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let selection = CGRect(x: screen.midX - 150, y: screen.maxY - 180, width: 300, height: 18)
        panel.show(model: self, near: selection, sourceName: "TextEdit", sourceIcon: Self.demoIcon)
    }
}
