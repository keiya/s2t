enum PipelineState: Sendable {
    case idle
    case recording
    case processing(step: ProcessingStep)
    case done(TranscriptionResult, CorrectionResult?)
    case error(PipelineError)
}

enum ProcessingStep: String, Sendable {
    case transcribing
    case correcting
    case speaking
}
