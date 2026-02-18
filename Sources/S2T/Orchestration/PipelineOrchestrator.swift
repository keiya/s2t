import Foundation
import os

@MainActor
@Observable
final class PipelineOrchestrator {
    var state: PipelineState = .idle
    var lastTranscription: TranscriptionResult?
    var lastCorrection: CorrectionResult?
    var showCopiedFeedback: Bool = false
    var audioLevel: Float = 0

    private let speechService: SpeechService
    private let transcriptionService: any TranscriptionService
    private let correctionService: any CorrectionService
    private let ttsService: TTSService
    private let clipboardService: ClipboardService
    private let copyCorrected: Bool

    private var currentTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

    init(
        speechService: SpeechService,
        transcriptionService: any TranscriptionService,
        correctionService: any CorrectionService,
        ttsService: TTSService,
        clipboardService: ClipboardService,
        copyCorrected: Bool = false
    ) {
        self.speechService = speechService
        self.transcriptionService = transcriptionService
        self.correctionService = correctionService
        self.ttsService = ttsService
        self.clipboardService = clipboardService
        self.copyCorrected = copyCorrected
    }

    // MARK: - Recording Control

    func startRecording() {
        // Ignore key repeat while already recording
        if case .recording = state { return }

        // Cancel any in-flight pipeline
        currentTask?.cancel()
        currentTask = nil

        // Stop TTS if playing
        ttsService.stopPlayback()

        // Reset correction
        lastCorrection = nil

        do {
            try speechService.startRecording()
            state = .recording
            startLevelMonitor()
            Logger.pipeline.info("Recording started")
        } catch {
            state = .error(.configurationError(error.localizedDescription))
            Logger.pipeline.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func startLevelMonitor() {
        levelTask?.cancel()
        levelTask = Task {
            while !Task.isCancelled, case .recording = state {
                audioLevel = speechService.currentLevel
                try? await Task.sleep(for: .milliseconds(50))
            }
            audioLevel = 0
        }
    }

    func stopRecordingAndProcess() {
        guard case .recording = state else {
            Logger.pipeline.warning("stopRecordingAndProcess called but not recording")
            return
        }

        let audioData = speechService.stopRecording()
        Logger.pipeline.info("Recording stopped, \(audioData.count) bytes captured")

        currentTask?.cancel()
        currentTask = Task {
            await processPipeline(audio: audioData)
        }
    }

    // MARK: - Pipeline

    private func processPipeline(audio: Data) async {
        // Step 1: Transcribe
        state = .processing(step: .transcribing)

        let transcription: TranscriptionResult
        do {
            transcription = try await transcriptionService.transcribe(audio)
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch let error as PipelineError {
            guard !Task.isCancelled else { return }
            state = .error(error)
            Logger.pipeline.error("Transcription failed: \(error.localizedDescription)")
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.transcriptionFailed(underlying: error.localizedDescription))
            Logger.pipeline.error("Transcription failed: \(error.localizedDescription)")
            return
        }

        guard !Task.isCancelled else { return }

        lastTranscription = transcription
        Logger.pipeline.info("Transcription: \(transcription.text.prefix(80))")

        // Copy raw transcript to clipboard immediately
        copyToClipboardWithFeedback(transcription.text)

        // Step 2: Correct
        state = .processing(step: .correcting)

        let correction: CorrectionResult?
        do {
            correction = try await correctionService.correct(transcript: transcription.text)
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // Correction failed — raw transcript already on clipboard
            Logger.pipeline.warning("Correction failed: \(error.localizedDescription)")
            correction = nil
        }

        guard !Task.isCancelled else { return }

        lastCorrection = correction

        // Copy corrected text if enabled
        if copyCorrected, let correctedText = correction?.correctedText {
            copyToClipboardWithFeedback(correctedText)
        }

        // Step 3: TTS (only if correction succeeded)
        if let correction {
            state = .processing(step: .speaking)
            do {
                try await ttsService.speak(correction.correctedText)
            } catch {
                // TTS failure is non-critical, continue silently
                Logger.tts.error("TTS failed (non-critical): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !Task.isCancelled else { return }

        state = .done(transcription, correction)
        Logger.pipeline.info("Pipeline complete")
    }

    // MARK: - Utilities

    func replayTTS() {
        guard let text = lastCorrection?.correctedText ?? lastTranscription?.text else {
            Logger.pipeline.warning("No text to replay")
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            state = .processing(step: .speaking)
            do {
                try await ttsService.speak(text)
            } catch {
                Logger.tts.warning("TTS replay failed: \(error.localizedDescription)")
            }
            guard !Task.isCancelled else { return }
            if let t = lastTranscription {
                state = .done(t, lastCorrection)
            }
        }
    }

    func copyRawTranscript() {
        guard let transcription = lastTranscription else { return }
        copyToClipboardWithFeedback(transcription.text)
    }

    func copyCorrectedText() {
        guard let correction = lastCorrection else { return }
        copyToClipboardWithFeedback(correction.correctedText)
    }

    private func copyToClipboardWithFeedback(_ text: String) {
        let copied = clipboardService.copyToClipboard(text)
        if copied {
            showCopiedFeedback = true
            feedbackTask?.cancel()
            feedbackTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled {
                    showCopiedFeedback = false
                }
            }
        } else {
            Logger.pipeline.warning("Clipboard copy failed")
        }
    }
}
