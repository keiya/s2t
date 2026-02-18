import Foundation
import TOMLDecoder
import os

struct AppConfig: Sendable, Codable {
    var api: ApiConfig
    var stt: SttConfig
    var correction: CorrectionConfig
    var tts: TtsConfig
    var input: InputConfig
    var clipboard: ClipboardConfig?

    struct ApiConfig: Sendable, Codable {
        var openaiKey: String

        enum CodingKeys: String, CodingKey {
            case openaiKey = "openai_key"
        }
    }

    struct SttConfig: Sendable, Codable {
        var model: String
        var timeout: Int

        enum CodingKeys: String, CodingKey {
            case model, timeout
        }
    }

    struct CorrectionConfig: Sendable, Codable {
        var model: String
        var timeout: Int
    }

    struct TtsConfig: Sendable, Codable {
        var model: String
        var voice: String
        var enabled: Bool
    }

    struct InputConfig: Sendable, Codable {
        var hotkey: [String]
    }

    struct ClipboardConfig: Sendable, Codable {
        var copyCorrected: Bool

        enum CodingKeys: String, CodingKey {
            case copyCorrected = "copy_corrected"
        }
    }

    // MARK: - Defaults

    static let `default` = AppConfig(
        api: ApiConfig(openaiKey: ""),
        stt: SttConfig(model: "gpt-4o-mini-transcribe", timeout: 60),
        correction: CorrectionConfig(model: "gpt-5-mini", timeout: 30),
        tts: TtsConfig(model: "gpt-4o-mini-tts", voice: "coral", enabled: true),
        input: InputConfig(hotkey: ["left_ctrl", "space"]),
        clipboard: ClipboardConfig(copyCorrected: false)
    )

    // MARK: - Loading

    static func configDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("org.keiya.s2t")
    }

    static func configFilePath() -> URL {
        configDirectory().appendingPathComponent("config.toml")
    }

    static func load() throws -> AppConfig {
        let path = configFilePath()
        Logger.config.info("Loading config from \(path.path, privacy: .public)")

        let tomlString: String
        do {
            tomlString = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw PipelineError.configurationError(
                "Cannot read config file at \(path.path): \(error.localizedDescription)"
            )
        }

        let expanded = expandEnvironmentVariables(in: tomlString)

        let config: AppConfig
        do {
            let decoder = TOMLDecoder()
            config = try decoder.decode(AppConfig.self, from: expanded)
        } catch {
            throw PipelineError.configurationError(
                "Failed to parse config.toml: \(error.localizedDescription)"
            )
        }

        try validate(config)
        Logger.config.info("Config loaded successfully")
        return config
    }

    /// Load from a TOML string (for testing).
    static func load(from tomlString: String) throws -> AppConfig {
        let expanded = expandEnvironmentVariables(in: tomlString)
        let decoder = TOMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: expanded)
        try validate(config)
        return config
    }

    // MARK: - Environment Variable Expansion

    static func expandEnvironmentVariables(in text: String) -> String {
        var result = text
        // Match ${VAR_NAME} pattern
        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let nsRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: nsRange)

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let varNameRange = Range(match.range(at: 1), in: result)
            else { continue }

            let varName = String(result[varNameRange])
            let value = ProcessInfo.processInfo.environment[varName] ?? ""
            result.replaceSubrange(fullRange, with: value)
        }

        return result
    }

    // MARK: - Validation

    static func validate(_ config: AppConfig) throws {
        if config.api.openaiKey.isEmpty {
            throw PipelineError.configurationError(
                "api.openai_key is required. Set OPENAI_API_KEY environment variable or configure it in config.toml."
            )
        }
    }
}
