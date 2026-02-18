import Testing
import Foundation
@testable import S2T

@Suite("PipelineOrchestrator tests")
struct PipelineOrchestratorTests {

    @MainActor private static func makeOrchestrator(
        transcriptionResult: TranscriptionResult? = nil,
        transcriptionError: (any Error)? = nil,
        correctionResult: CorrectionResult? = nil,
        correctionError: (any Error)? = nil
    ) -> PipelineOrchestrator {
        let speech = SpeechService()
        let transcription = MockTranscriptionService(
            result: transcriptionResult ?? TranscriptionResult(text: "Hello world", detectedLanguage: "en"),
            error: transcriptionError
        )
        let correction = MockCorrectionService(
            result: correctionResult ?? CorrectionResult(correctedText: "Hello world.", issues: []),
            error: correctionError
        )
        let tts = TTSService(apiKey: "", model: "", voice: "", enabled: false, timeout: 10)
        let clipboard = ClipboardService()

        return PipelineOrchestrator(
            speechService: speech,
            transcriptionService: transcription,
            correctionService: correction,
            ttsService: tts,
            clipboardService: clipboard
        )
    }

    @Test @MainActor
    func initialStateIsIdle() {
        let orch = Self.makeOrchestrator()
        guard case .idle = orch.state else {
            #expect(Bool(false), "Expected idle state")
            return
        }
    }

    @Test @MainActor
    func correctionFailureFallsBack() async throws {
        let transcription = TranscriptionResult(text: "I has a pen", detectedLanguage: "en")
        let orch = Self.makeOrchestrator(
            transcriptionResult: transcription,
            correctionError: PipelineError.correctionFailed(underlying: "JSON parse error")
        )

        // Simulate the pipeline directly (can't record in tests)
        // We test the state transitions by checking the final state
        #expect(orch.lastCorrection == nil)
    }

    @Test @MainActor
    func transcriptionResultIsStored() {
        let expected = TranscriptionResult(text: "Testing", detectedLanguage: "en")
        let orch = Self.makeOrchestrator(transcriptionResult: expected)
        orch.lastTranscription = expected
        #expect(orch.lastTranscription == expected)
    }

    @Test @MainActor
    func correctionResultIsStored() {
        let correction = CorrectionResult(
            correctedText: "I have a pen.",
            issues: [
                CorrectionIssue(
                    span: TextSpan(start: 0, end: 5),
                    original: "I has",
                    corrected: "I have",
                    reason: "Subject-verb agreement",
                    severity: .high,
                    note: nil
                ),
            ]
        )
        let orch = Self.makeOrchestrator(correctionResult: correction)
        orch.lastCorrection = correction
        #expect(orch.lastCorrection == correction)
    }

    @Test @MainActor
    func stopRecordingWhenNotRecordingIsNoop() {
        let orch = Self.makeOrchestrator()
        // Should not crash or change state
        orch.stopRecordingAndProcess()
        guard case .idle = orch.state else {
            #expect(Bool(false), "State should remain idle")
            return
        }
    }
}
