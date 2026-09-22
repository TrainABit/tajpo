import AppKit
import Combine
import TajpoCore

/// State of the inline panel for one captured selection. Kept separate from
/// `AppModel` so streamed tokens only re-render the panel.
@MainActor
final class RewriteSession: ObservableObject {
    enum Phase: Equatable {
        case capturing, ready, running, finished, failed
    }

    @Published private(set) var phase: Phase = .capturing
    @Published private(set) var capture: TextCapture?
    @Published private(set) var action: RewriteAction?
    @Published var tone: RewriteTone = .professional
    /// Text of the "Tell Tajpo what to do" field for the custom action.
    @Published var instruction = ""
    /// Set to move keyboard focus to the instruction field.
    @Published var focusInstruction = false
    @Published private(set) var preview = ""
    /// Final replacement text. Only set for complete, usable results.
    @Published private(set) var result: String?
    @Published private(set) var diff: [DiffSegment]?
    @Published private(set) var error: TajpoError?
    @Published private(set) var notice: String?
    @Published var isReplacing = false
    /// A one-time feature tip shown under the result.
    @Published var tip: String?
    @Published var showChanges = true
    /// The app the text came from, shown in the panel header.
    @Published var sourceName: String?
    @Published var sourceIcon: NSImage?

    /// Increases on every reset, so async work can tell its session is gone.
    private(set) var generation = 0

    func reset() {
        generation += 1
        phase = .capturing
        capture = nil
        action = nil
        preview = ""
        result = nil
        diff = nil
        error = nil
        notice = nil
        isReplacing = false
        instruction = ""
        tip = nil
    }

    func captured(_ capture: TextCapture) {
        self.capture = capture
        error = nil
        phase = .ready
    }

    func begin(_ action: RewriteAction) {
        self.action = action
        phase = .running
        preview = ""
        result = nil
        diff = nil
        error = nil
        notice = nil
        showChanges = action == .correct
    }

    func update(preview: String) {
        guard phase == .running else { return }
        self.preview = preview
    }

    func finish(_ text: String) {
        result = text
        preview = text
        diff = capture.flatMap { WordDiff.diff(from: $0.text, to: text) }
        phase = .finished
    }

    func fail(_ error: TajpoError) {
        self.error = error
        phase = .failed
    }

    /// Shows an error without discarding a finished result (e.g. a failed Replace).
    func report(_ error: TajpoError) {
        self.error = error
        notice = nil
    }

    func cancelled() {
        phase = result == nil ? .ready : .finished
        error = nil
    }

    func note(_ message: String) {
        notice = message
        error = nil
    }

    var isRunning: Bool { phase == .running }

    var canRun: Bool { capture != nil && !isRunning && !isReplacing }

    var canReplace: Bool {
        guard let capture, result != nil, !isRunning, !isReplacing else { return false }
        return capture.canReplace
    }

    /// Text available to copy: the result, or the partial preview after a failure.
    var copyableText: String? {
        if let result { return result }
        return preview.isEmpty ? nil : preview
    }
}
