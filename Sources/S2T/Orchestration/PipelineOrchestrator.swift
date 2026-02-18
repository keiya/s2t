import AppKit
import AVFoundation
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
    private let windowTitleService: WindowTitleService
    private let copyCorrected: Bool

    private var transcriptHistory = TranscriptHistory()
    private var currentWindowTitle: String?

    private var currentTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var audioConfigTask: Task<Void, Never>?
    private var configChangeRestartCount = 0

    init(
        speechService: SpeechService,
        transcriptionService: any TranscriptionService,
        correctionService: any CorrectionService,
        ttsService: TTSService,
        clipboardService: ClipboardService,
        copyCorrected: Bool = false,
        windowTitleService: WindowTitleService = WindowTitleService()
    ) {
        self.speechService = speechService
        self.transcriptionService = transcriptionService
        self.correctionService = correctionService
        self.ttsService = ttsService
        self.clipboardService = clipboardService
        self.copyCorrected = copyCorrected
        self.windowTitleService = windowTitleService
        startAudioConfigObserver()
    }

    // MARK: - Recording Control

    func startRecording() {
        if case .recording = state { return }

        // Capture window title before any state changes (while the user's target window is still frontmost)
        currentWindowTitle = windowTitleService.frontmostWindowTitle()
        Logger.pipeline.info("Window title: \(self.currentWindowTitle ?? "none", privacy: .public)")

        // Check microphone permission before attempting to record
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            state = .error(.configurationError(
                "Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone."
            ))
            return
        }

        // Cancel any in-flight pipeline
        currentTask?.cancel()
        currentTask = nil

        // Stop TTS if playing
        ttsService.stopPlayback()

        do {
            try speechService.startRecording()
            state = .recording
            configChangeRestartCount = 0
            startLevelMonitor()
            Logger.pipeline.info("Recording started")
        } catch {
            state = .error(.configurationError(error.localizedDescription))
            Logger.pipeline.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
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

        let audio = speechService.stopRecording()
        Logger.pipeline.info("Recording stopped, \(audio.data.count) bytes captured (\(audio.filename))")

        currentTask?.cancel()
        currentTask = Task {
            await processPipeline(audio: audio)
        }
    }

    // MARK: - Pipeline

    private func processPipeline(audio: RecordedAudio) async {
        // Clear previous results now that processing begins
        lastTranscription = nil
        lastCorrection = nil

        // Step 1: Transcribe
        state = .processing(step: .transcribing)

        let prompt = transcriptHistory.buildPrompt(windowTitle: currentWindowTitle)
        Logger.pipeline.info("STT prompt: \(prompt ?? "none", privacy: .public)")

        let transcription: TranscriptionResult
        do {
            transcription = try await transcriptionService.transcribe(audio, prompt: prompt)
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

        // Update transcript history for future STT prompting (prefer corrected text)
        let historyText = correction?.correctedText ?? transcription.text
        transcriptHistory.append(historyText, forTitle: currentWindowTitle)

        // Copy corrected text if enabled
        if copyCorrected, let correctedText = correction?.correctedText {
            copyToClipboardWithFeedback(correctedText)
        }

        state = .done(transcription, correction)
        Logger.pipeline.info("Pipeline complete")

        // TTS plays only when there are corrections — skip if text was already correct
        if let correction, !correction.issues.isEmpty {
            do {
                try await ttsService.speak(correction.correctedText)
            } catch {
                Logger.tts.error("TTS failed (non-critical): \(error.localizedDescription, privacy: .public)")
            }
        }
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

    // MARK: - Audio Device Changes

    private func startAudioConfigObserver() {
        audioConfigTask = Task {
            for await _ in NotificationCenter.default.notifications(
                named: .AVAudioEngineConfigurationChange
            ) {
                guard !Task.isCancelled else { break }
                handleAudioConfigChange()
            }
        }
    }

    private func handleAudioConfigChange() {
        Logger.audio.warning("Audio device configuration changed")

        guard case .recording = state else {
            // Not recording — just reset engine for next use
            speechService.reset()
            return
        }

        // The system has already stopped and uninitialized the engine.
        // Restart recording with the new audio configuration.
        configChangeRestartCount += 1
        if configChangeRestartCount > 2 {
            speechService.reset()
            state = .error(.configurationError(
                "Audio device changed repeatedly. Please try again."
            ))
            return
        }

        Logger.audio.info("Restarting recording after config change (attempt \(self.configChangeRestartCount))")
        speechService.reset()
        do {
            try speechService.startRecording()
            startLevelMonitor()
        } catch {
            state = .error(.configurationError(
                "Failed to restart recording: \(error.localizedDescription)"
            ))
        }
    }
}
