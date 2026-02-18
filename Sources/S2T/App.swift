import AVFoundation
import SwiftUI
import os

@main
struct S2TApp: App {
    @State private var orchestrator: PipelineOrchestrator?
    @State private var configError: String?
    @State private var hotkeyService: HotkeyService?
    @State private var permissionWarning: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let orchestrator {
                    VStack(spacing: 0) {
                        if let permissionWarning {
                            permissionBanner(message: permissionWarning)
                        }
                        ContentView(orchestrator: orchestrator)
                    }
                } else if let configError {
                    errorView(message: configError)
                } else {
                    ProgressView("Loading...")
                        .frame(width: 480, height: 300)
                }
            }
            .task {
                await initialize()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private func initialize() async {
        // SPM-launched apps default to background (accessory) process.
        // Set to regular to appear in Dock and Cmd+Tab.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Ensure config directory exists
        ensureConfigDirectory()

        // Load config
        let config: AppConfig
        do {
            config = try AppConfig.load()
        } catch {
            configError = error.localizedDescription
            Logger.config.error("Config load failed: \(error.localizedDescription)")
            return
        }

        // Request microphone permission
        let micGranted = await requestMicrophonePermission()
        if !micGranted {
            permissionWarning = "Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone."
            Logger.audio.warning("Microphone permission not granted")
        }

        // Check accessibility permission
        if !HotkeyService.checkAccessibilityPermission() {
            let msg = "Accessibility permission required for global hotkey. Grant in System Settings > Privacy & Security > Accessibility."
            if permissionWarning != nil {
                permissionWarning = permissionWarning.map { $0 + "\n" + msg }
            } else {
                permissionWarning = msg
            }
            Logger.hotkey.warning("Accessibility permission not granted")
        }

        // Create services
        let speechService = SpeechService()
        let transcriptionService = OpenAITranscriptionService(
            apiKey: config.api.openaiKey,
            model: config.stt.model,
            timeout: TimeInterval(config.stt.timeout)
        )
        let correctionService = OpenAICorrectionService(
            apiKey: config.api.openaiKey,
            model: config.correction.model,
            timeout: TimeInterval(config.correction.timeout)
        )
        let ttsService = TTSService(config: config)
        let clipboardService = ClipboardService()

        // Create orchestrator
        let orch = PipelineOrchestrator(
            speechService: speechService,
            transcriptionService: transcriptionService,
            correctionService: correctionService,
            ttsService: ttsService,
            clipboardService: clipboardService,
            copyCorrected: config.clipboard?.copyCorrected ?? false
        )
        self.orchestrator = orch

        // Setup hotkey
        let hotkey = HotkeyService(
            hotkey: config.input.hotkey,
            onHotkeyDown: { [orch] in
                orch.startRecording()
            },
            onHotkeyUp: { [orch] in
                orch.stopRecordingAndProcess()
            }
        )

        do {
            try hotkey.start()
            self.hotkeyService = hotkey
        } catch {
            Logger.hotkey.error("Hotkey setup failed: \(error.localizedDescription)")
        }

        Logger.pipeline.info("S2T initialized successfully")
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.audio.error("Microphone auth status: \(String(describing: status.rawValue), privacy: .public)")
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            Logger.audio.error("Microphone permission request result: \(granted, privacy: .public)")
            return granted
        default:
            return false
        }
    }

    // MARK: - Config Directory

    private func ensureConfigDirectory() {
        let dir = AppConfig.configDirectory()
        do {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                Logger.config.info("Created config directory at \(dir.path)")
            }

            let configPath = AppConfig.configFilePath()
            if !FileManager.default.fileExists(atPath: configPath.path) {
                let sampleConfig = """
                [api]
                openai_key = "${OPENAI_API_KEY}"

                [stt]
                model = "gpt-4o-mini-transcribe"
                timeout = 60

                [correction]
                model = "gpt-5-mini"
                timeout = 30

                [tts]
                model = "gpt-4o-mini-tts"
                voice = "coral"
                enabled = true

                [input]
                hotkey = ["left_ctrl", "space"]

                [clipboard]
                copy_corrected = false
                """
                try sampleConfig.write(to: configPath, atomically: true, encoding: .utf8)
                Logger.config.info("Created sample config at \(configPath.path)")
            }
        } catch {
            Logger.config.error("Failed to set up config: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Views

    private func permissionBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
                )
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(10)
        .background(.yellow.opacity(0.1))
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text("Configuration Error")
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Text("Edit config at:\n\(AppConfig.configFilePath().path)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button("Open Config Folder") {
                NSWorkspace.shared.open(AppConfig.configDirectory())
            }
        }
        .padding(32)
        .frame(width: 480, height: 300)
    }
}
