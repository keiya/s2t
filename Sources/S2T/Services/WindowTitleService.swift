import AppKit

/// Detects the frontmost window title using the Accessibility API.
/// Requires Accessibility permission (already granted for CGEventTap hotkey).
struct WindowTitleService: Sendable {

    /// Returns the title of the frontmost window, excluding this app's own windows.
    /// Returns nil on any failure — this is best-effort context for STT prompting.
    @MainActor
    func frontmostWindowTitle() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        // Skip our own app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard windowResult == .success, let window = focusedWindow else {
            return nil
        }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            // swiftlint:disable:next force_cast
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        guard titleResult == .success, let title = titleValue as? String, !title.isEmpty else {
            return nil
        }

        return title
    }
}
