import Testing
@testable import S2T

@Suite("ClipboardService tests")
struct ClipboardServiceTests {

    @Test
    func clipboardServiceExists() {
        // ClipboardService is a simple struct wrapping NSPasteboard.
        // Actual pasteboard operations require a GUI context which isn't
        // available in the test runner. Verify the type compiles and instantiates.
        let service = ClipboardService()
        _ = service
    }
}
