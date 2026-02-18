import Foundation
@testable import S2T

struct MockTranscriptionService: TranscriptionService {
    var result: TranscriptionResult?
    var error: (any Error)?

    func transcribe(_ audio: RecordedAudio, prompt: String? = nil) async throws -> TranscriptionResult {
        if let error { throw error }
        return result ?? TranscriptionResult(text: "mock transcription", detectedLanguage: "en")
    }
}

struct MockCorrectionService: CorrectionService {
    var result: CorrectionResult?
    var error: (any Error)?

    func correct(transcript: String) async throws -> CorrectionResult {
        if let error { throw error }
        return result ?? CorrectionResult(correctedText: transcript, issues: [])
    }
}
