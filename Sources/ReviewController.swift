import SwiftUI
import AppKit

/// Exposes the hosting NSWindow to its SwiftUI ancestor via a callback.
/// Placed as a background on ContentView to resolve the window reference.
struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in onResolve(v?.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onResolve(nsView?.window) }
    }
}

/// Owns all Review-Mode UI state + the NSEvent key monitor.
/// ContentView hooks action callbacks on appear.
final class ReviewController: ObservableObject {
    // Mode
    @Published var reviewMode: Bool = false
    @Published var showDrawer: Bool = true
    @Published var showCheatsheet: Bool = false

    // Comment editor
    @Published var showCommentEditor: Bool = false
    @Published var pendingAnchor: ReviewAnchor? = nil
    @Published var pendingAnchorIsHeading: Bool = false
    @Published var pendingSuggestFocused: Bool = false
    @Published var pendingSeverity: Severity? = nil
    @Published var editingComment: ReviewComment? = nil

    // Draft payload sheet
    @Published var showDraftPayload: Bool = false
    @Published var draftPayloadMarkdown: String = ""
    @Published var draftPayloadJSON: String = ""
    @Published var draftPayloadSummary: String = ""

    // Flash messages (transient)
    @Published var flash: String? = nil

    // Actions — wired up by the view
    var onCommentFocused: (_ withSuggest: Bool) -> Void = { _ in }
    var onApproveSubtree: () -> Void = { }
    var onResolveSelected: () -> Void = { }
    var onSelectNextComment: (_ unresolvedOnly: Bool) -> Void = { _ in }
    var onSelectPrevComment: (_ unresolvedOnly: Bool) -> Void = { _ in }
    var onJumpTop: () -> Void = { }
    var onJumpBottom: () -> Void = { }
    var onFinishReview: () -> Void = { }
    var onMoveBlockFocus: (_ delta: Int) -> Void = { _ in }

    private var monitor: Any?
    weak var hostingWindow: NSWindow?

    func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.reviewMode else { return event }

            // Multi-window: only the controller whose window is key should act.
            if let own = self.hostingWindow,
               let key = NSApp.keyWindow,
               own !== key {
                return event
            }

            // Don't steal keys from text editors / find bars etc.
            if let fr = NSApp.keyWindow?.firstResponder,
               (fr is NSTextView || fr is NSText) {
                return event
            }

            // Ignore keys while sheets are up (they handle their own input).
            if self.showCommentEditor || self.showDraftPayload { return event }

            if self.handle(event) {
                return nil
            }
            return event
        }
    }

    func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit { removeMonitor() }

    // MARK: - Key dispatch

    private func handle(_ event: NSEvent) -> Bool {
        // Cmd / Ctrl / Alt modifiers: don't intercept — SwiftUI / menu handles those.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modsDisallowed: NSEvent.ModifierFlags = [.command, .control, .option]
        if !flags.intersection(modsDisallowed).isEmpty { return false }

        // Esc
        if event.keyCode == 53 {
            if showCheatsheet { showCheatsheet = false; return true }
            if showCommentEditor {
                // Close editor panel (inline in drawer — keep sheet-less Esc path)
                withAnimationBlock {
                    self.showCommentEditor = false
                    self.pendingAnchor = nil
                    self.editingComment = nil
                    self.pendingSeverity = nil
                }
                return true
            }
            return false
        }

        // Arrow keys — block focus navigation
        if event.keyCode == 125 { onMoveBlockFocus(1);  return true }  // down
        if event.keyCode == 126 { onMoveBlockFocus(-1); return true }  // up

        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }

        switch chars {
        case "c":
            pendingSeverity = nil
            onCommentFocused(false)
            return true
        case "s":
            pendingSeverity = nil
            onCommentFocused(true)
            return true
        case "a":
            onApproveSubtree()
            return true
        case "r":
            onResolveSelected()
            return true
        case "j":
            onSelectNextComment(false)
            return true
        case "k":
            onSelectPrevComment(false)
            return true
        case "n":
            onSelectNextComment(true)
            return true
        case "N":
            onSelectPrevComment(true)
            return true
        case "g":
            onJumpTop()
            return true
        case "G":
            onJumpBottom()
            return true
        case "!":
            pendingSeverity = .blocker
            onCommentFocused(false)
            return true
        case "q":
            pendingSeverity = .question
            onCommentFocused(false)
            return true
        case ".":
            pendingSeverity = .nitpick
            onCommentFocused(false)
            return true
        case "?":
            showCheatsheet.toggle()
            return true
        default:
            return false
        }
    }

    // MARK: - Flash helper

    func bindWindow(_ w: NSWindow?) {
        hostingWindow = w
    }

    /// Run a mutation inside an animation block, safely on the main actor.
    func withAnimationBlock(_ body: () -> Void) {
        withAnimation(.easeInOut(duration: 0.18)) { body() }
    }

    func showFlash(_ message: String) {
        flash = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.flash == message { self?.flash = nil }
        }
    }
}
