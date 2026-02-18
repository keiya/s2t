import Testing
@testable import S2T

@Suite("TranscriptHistory tests")
struct TranscriptHistoryTests {

    @Test
    func emptyHistoryReturnsNil() {
        let history = TranscriptHistory()
        #expect(history.history(forTitle: "Safari") == nil)
        #expect(history.history(forTitle: nil) == nil)
    }

    @Test
    func appendAndRetrieve() {
        var history = TranscriptHistory()
        history.append("Hello world", forTitle: "Safari")
        #expect(history.history(forTitle: "Safari") == "Hello world")
    }

    @Test
    func appendAccumulatesText() {
        var history = TranscriptHistory()
        history.append("Hello", forTitle: "Safari")
        history.append("world", forTitle: "Safari")
        #expect(history.history(forTitle: "Safari") == "Hello world")
    }

    @Test
    func perTitleIsolation() {
        var history = TranscriptHistory()
        history.append("Safari text", forTitle: "Safari")
        history.append("Slack text", forTitle: "Slack")

        #expect(history.history(forTitle: "Safari") == "Safari text")
        #expect(history.history(forTitle: "Slack") == "Slack text")
    }

    @Test
    func nilTitleUsesEmptyKey() {
        var history = TranscriptHistory()
        history.append("no title text", forTitle: nil)
        #expect(history.history(forTitle: nil) == "no title text")
        #expect(history.history(forTitle: "Safari") == nil)
    }

    @Test
    func truncationAddsEllipsis() {
        var history = TranscriptHistory(maxWords: 5)
        // 7 words total — should truncate to last 5 with "..." prefix
        history.append("one two three four five six seven", forTitle: "Test")
        let result = history.history(forTitle: "Test")
        #expect(result == "... three four five six seven")
    }

    @Test
    func truncationAcrossMultipleAppends() {
        var history = TranscriptHistory(maxWords: 3)
        history.append("alpha beta", forTitle: "Test")
        history.append("gamma delta", forTitle: "Test")
        // 4 words total, max 3 → keep last 3 with "..."
        let result = history.history(forTitle: "Test")
        #expect(result == "... beta gamma delta")
    }

    @Test
    func exactMaxWordsNoEllipsis() {
        var history = TranscriptHistory(maxWords: 3)
        history.append("one two three", forTitle: "Test")
        #expect(history.history(forTitle: "Test") == "one two three")
    }

    @Test
    func buildPromptWithTitleAndHistory() {
        var history = TranscriptHistory()
        history.append("previous text here", forTitle: "Safari")
        let prompt = history.buildPrompt(windowTitle: "Safari")
        #expect(prompt == "The user is dictating in Safari.\nprevious text here")
    }

    @Test
    func buildPromptWithTitleOnly() {
        let history = TranscriptHistory()
        let prompt = history.buildPrompt(windowTitle: "Safari")
        #expect(prompt == "The user is dictating in Safari.")
    }

    @Test
    func buildPromptWithHistoryOnly() {
        var history = TranscriptHistory()
        history.append("some words", forTitle: nil)
        let prompt = history.buildPrompt(windowTitle: nil)
        #expect(prompt == "some words")
    }

    @Test
    func buildPromptWithNothingReturnsNil() {
        let history = TranscriptHistory()
        #expect(history.buildPrompt(windowTitle: nil) == nil)
    }

    @Test
    func buildPromptWithEmptyTitleReturnsNil() {
        let history = TranscriptHistory()
        #expect(history.buildPrompt(windowTitle: "") == nil)
    }
}
