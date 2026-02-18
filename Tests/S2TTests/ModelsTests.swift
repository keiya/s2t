import Testing
import Foundation
@testable import S2T

@Suite("Model Codable round-trip tests")
struct ModelsTests {

    @Test
    func transcriptionResultRoundTrip() throws {
        let original = TranscriptionResult(text: "Hello world", detectedLanguage: "en")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func transcriptionResultWithNilLanguage() throws {
        let original = TranscriptionResult(text: "Hello", detectedLanguage: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        #expect(decoded == original)
        #expect(decoded.detectedLanguage == nil)
    }

    @Test
    func correctionResultRoundTrip() throws {
        let original = CorrectionResult(
            correctedText: "I have a pen.",
            issues: [
                CorrectionIssue(
                    span: TextSpan(start: 0, end: 5),
                    original: "I has",
                    corrected: "I have",
                    reason: "Subject-verb agreement",
                    severity: .high,
                    note: "Use 'have' with first-person singular subject"
                ),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CorrectionResult.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func correctionResultFromJSON() throws {
        let json = """
        {
          "corrected_text": "She goes to school.",
          "issues": [
            {
              "span": { "start": 4, "end": 6 },
              "original": "go",
              "corrected": "goes",
              "reason": "Third-person singular",
              "severity": "medium",
              "note": null
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(CorrectionResult.self, from: data)
        #expect(result.correctedText == "She goes to school.")
        #expect(result.issues.count == 1)
        #expect(result.issues[0].severity == .medium)
        #expect(result.issues[0].note == nil)
    }

    @Test
    func severityAllCases() throws {
        for severity in [Severity.low, .medium, .high] {
            let json = "\"\(severity.rawValue)\""
            let decoded = try JSONDecoder().decode(Severity.self, from: Data(json.utf8))
            #expect(decoded == severity)
        }
    }

    @Test
    func pipelineErrorDescriptions() {
        let errors: [PipelineError] = [
            .audioTooShort,
            .transcriptionFailed(underlying: "test"),
            .correctionFailed(underlying: "test"),
            .ttsFailed(underlying: "test"),
            .clipboardFailed,
            .configurationError("test"),
            .authenticationError,
            .rateLimited,
            .timeout,
            .networkError(underlying: "test"),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }
}
