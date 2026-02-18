import Foundation
import os

protocol TranscriptionService: Sendable {
    func transcribe(_ audio: Data) async throws -> TranscriptionResult
}

struct OpenAITranscriptionService: TranscriptionService {
    let apiKey: String
    let model: String
    let timeout: TimeInterval

    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    func transcribe(_ audio: Data) async throws -> TranscriptionResult {
        guard audio.count > SpeechService.minimumAudioDataSize else {
            throw PipelineError.audioTooShort
        }

        let boundary = UUID().uuidString
        var body = Data()

        // file field (WAV)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n")

        // model field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(model)\r\n")

        // language field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append("en\r\n")

        // response_format field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("json\r\n")

        body.append("--\(boundary)--\r\n")

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = timeout

        Logger.stt.info("Sending transcription request (\(audio.count) bytes)")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PipelineError.networkError(underlying: "Invalid response")
        }

        try Self.checkHTTPStatus(httpResponse, data: data)

        let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
        Logger.stt.error("STT raw response: \(rawBody, privacy: .public)")

        let apiResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
        let result = TranscriptionResult(
            text: apiResponse.text,
            detectedLanguage: apiResponse.language
        )

        Logger.stt.error("Transcription result text: [\(result.text, privacy: .public)]")
        return result
    }

    private static func checkHTTPStatus(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200: return
        case 401:
            throw PipelineError.authenticationError
        case 429:
            throw PipelineError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw PipelineError.transcriptionFailed(
                underlying: "HTTP \(response.statusCode): \(body)"
            )
        }
    }
}

// OpenAI Whisper API response
private struct WhisperResponse: Codable {
    let text: String
    let language: String?
}

// Helper for building multipart form data
private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
