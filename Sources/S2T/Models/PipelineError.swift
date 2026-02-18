import Foundation

enum PipelineError: Error, LocalizedError, Sendable {
    case audioTooShort
    case transcriptionFailed(underlying: String)
    case correctionFailed(underlying: String)
    case ttsFailed(underlying: String)
    case clipboardFailed
    case configurationError(String)
    case authenticationError
    case rateLimited
    case timeout
    case networkError(underlying: String)

    var errorDescription: String? {
        switch self {
        case .audioTooShort:
            "Recording too short. Please speak longer."
        case .transcriptionFailed(let msg):
            "Transcription failed: \(msg)"
        case .correctionFailed(let msg):
            "Correction failed: \(msg)"
        case .ttsFailed(let msg):
            "TTS failed: \(msg)"
        case .clipboardFailed:
            "Failed to copy to clipboard."
        case .configurationError(let msg):
            "Configuration error: \(msg)"
        case .authenticationError:
            "Authentication failed. Check your API key."
        case .rateLimited:
            "Rate limited. Please wait and try again."
        case .timeout:
            "Request timed out."
        case .networkError(let msg):
            "Network error: \(msg)"
        }
    }
}
