import Testing
import Foundation
@testable import S2T

@Suite("TranscriptionService tests")
struct TranscriptionServiceTests {

    @Test
    func mockTranscriptionReturnsResult() async throws {
        let expected = TranscriptionResult(text: "Hello world", detectedLanguage: "en")
        let service = MockTranscriptionService(result: expected)
        let result = try await service.transcribe(Data(repeating: 0, count: 100))
        #expect(result == expected)
    }

    @Test
    func mockTranscriptionThrowsError() async {
        let service = MockTranscriptionService(error: PipelineError.audioTooShort)
        do {
            _ = try await service.transcribe(Data())
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is PipelineError)
        }
    }

    @Test
    func audioTooShortThrows() async {
        let service = OpenAITranscriptionService(
            apiKey: "test-key",
            model: "gpt-4o-mini-transcribe",
            timeout: 10
        )
        // Send data smaller than minimum
        let tinyAudio = Data(repeating: 0, count: 100)
        do {
            _ = try await service.transcribe(tinyAudio)
            #expect(Bool(false), "Should have thrown audioTooShort")
        } catch let error as PipelineError {
            if case .audioTooShort = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected audioTooShort, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}
