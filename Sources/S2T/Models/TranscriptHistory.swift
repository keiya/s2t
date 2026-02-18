/// Per-window-title ring buffer of recent transcript text.
/// Used to build STT prompt context for improved recognition accuracy.
struct TranscriptHistory: Sendable {
    private var buffers: [String: String] = [:]
    let maxWords: Int

    init(maxWords: Int = 100) {
        self.maxWords = maxWords
    }

    /// Append text to the history buffer for the given window title.
    mutating func append(_ text: String, forTitle title: String?) {
        let key = title ?? ""
        let existing = buffers[key, default: ""]
        let combined = existing.isEmpty ? text : "\(existing) \(text)"
        let words = combined.split(separator: " ")
        if words.count > maxWords {
            buffers[key] = "... " + words.suffix(maxWords).joined(separator: " ")
        } else {
            buffers[key] = words.joined(separator: " ")
        }
    }

    /// Retrieve the history buffer for a given window title.
    func history(forTitle title: String?) -> String? {
        let key = title ?? ""
        let value = buffers[key]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Build a combined prompt string from window title context and transcript history.
    /// Returns nil if there is nothing useful to include.
    func buildPrompt(windowTitle: String?) -> String? {
        var parts: [String] = []

        if let title = windowTitle, !title.isEmpty {
            parts.append("The user is dictating in \(title).")
        }

        if let hist = history(forTitle: windowTitle) {
            parts.append(hist)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
