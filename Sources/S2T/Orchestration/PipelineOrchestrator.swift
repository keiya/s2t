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
    private let copyCorrected: Bool

    private var currentTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var audioConfigTask: Task<Void, Never>?
    private var configChangeRestartCount = 0

    /// Tracks whether the hotkey is currently held down.
    /// Prevents key repeat from re-triggering startRecording after a config change error.
    private var isHotkeyHeld = false

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
        startAudioConfigObserver()
    }

    // MARK: - Recording Control

    func startRecording() {
        // Ignore key repeat — only the first keyDown should start recording.
        // Without this, config change errors cause state != .recording, and
        // subsequent key repeats re-trigger startRecording in a loop.
        guard !isHotkeyHeld else { return }
        isHotkeyHeld = true

        if case .recording = state { return }

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
        isHotkeyHeld = false

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

        state = .done(transcription, correction)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.mainWindow?.orderFrontRegardless()
        Logger.pipeline.info("Pipeline complete")

        // TTS plays in the background — don't block .done state
        if let correction {
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
