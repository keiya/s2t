import AppKit
import os

struct ClipboardService: Sendable {
    func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        if success {
            Logger.pipeline.info("Copied to clipboard (\(text.count) chars)")
        } else {
            Logger.pipeline.error("Failed to copy to clipboard")
        }
        return success
    }
}
