@preconcurrency import AVFoundation
import Foundation
import os

/// TTS service using OpenAI's text-to-speech API.
/// Not @MainActor — AVAudioPlayer callbacks can run on various threads.
/// @unchecked Sendable due to AVAudioPlayer's non-Sendable nature.
final class TTSService: @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let voice: String
    private let isEnabled: Bool
    private let timeout: TimeInterval

    private var player: AVAudioPlayer?

    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!

    init(config: AppConfig) {
        self.apiKey = config.api.openaiKey
        self.model = config.tts.model
        self.voice = config.tts.voice
        self.isEnabled = config.tts.enabled
        self.timeout = TimeInterval(config.stt.timeout)
    }

    init(apiKey: String, model: String, voice: String, enabled: Bool, timeout: TimeInterval) {
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.isEnabled = enabled
        self.timeout = timeout
    }

    func speak(_ text: String) async throws {
        guard isEnabled else {
            Logger.tts.debug("TTS disabled, skipping")
            return
        }

        let requestBody: [String: String] = [
            "model": model,
            "input": text,
            "voice": voice,
        ]

        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        Logger.tts.info("Requesting TTS for text (\(text.count) chars)")

        let (data, response) = try await URLSession.shared.upload(for: request, from: bodyData)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PipelineError.ttsFailed(underlying: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw PipelineError.ttsFailed(underlying: "HTTP \(httpResponse.statusCode): \(body)")
        }

        Logger.tts.info("TTS audio received (\(data.count) bytes), playing")

        let audioPlayer = try AVAudioPlayer(data: data)
        self.player = audioPlayer
        audioPlayer.play()

        // Wait for playback to complete
        while audioPlayer.isPlaying {
            try await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled {
                audioPlayer.stop()
                self.player = nil
                return
            }
        }
        self.player = nil
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        Logger.tts.debug("TTS playback stopped")
    }
}
