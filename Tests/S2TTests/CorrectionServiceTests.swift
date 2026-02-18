import Testing
import Foundation
@testable import S2T

@Suite("CorrectionService tests")
struct CorrectionServiceTests {

    @Test
    func mockCorrectionReturnsResult() async throws {
        let expected = CorrectionResult(
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
        let service = MockCorrectionService(result: expected)
        let result = try await service.correct(transcript: "I has a pen.")
        #expect(result == expected)
    }

    @Test
    func mockCorrectionThrowsError() async {
        let service = MockCorrectionService(
            error: PipelineError.correctionFailed(underlying: "test")
        )
        do {
            _ = try await service.correct(transcript: "test")
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is PipelineError)
        }
    }

    @Test
    func noIssuesForCorrectText() async throws {
        let service = MockCorrectionService(
            result: CorrectionResult(correctedText: "This is correct.", issues: [])
        )
        let result = try await service.correct(transcript: "This is correct.")
        #expect(result.correctedText == "This is correct.")
        #expect(result.issues.isEmpty)
    }
}
