import Testing
import Foundation
@testable import S2T

@Suite("AppConfig tests")
struct AppConfigTests {

    static let validTOML = """
    [api]
    openai_key = "sk-test-key-12345"

    [stt]
    model = "gpt-4o-mini-transcribe"
    timeout = 30

    [correction]
    model = "gpt-5-mini"
    timeout = 30

    [tts]
    model = "gpt-4o-mini-tts"
    voice = "coral"
    enabled = true

    [input]
    hotkey = ["left_ctrl", "space"]
    """

    @Test
    func loadValidTOML() throws {
        let config = try AppConfig.load(from: Self.validTOML)
        #expect(config.api.openaiKey == "sk-test-key-12345")
        #expect(config.stt.model == "gpt-4o-mini-transcribe")
        #expect(config.stt.timeout == 30)
        #expect(config.correction.model == "gpt-5-mini")
        #expect(config.correction.timeout == 30)
        #expect(config.tts.model == "gpt-4o-mini-tts")
        #expect(config.tts.voice == "coral")
        #expect(config.tts.enabled == true)
        #expect(config.input.hotkey == ["left_ctrl", "space"])
    }

    @Test
    func environmentVariableExpansion() {
        let input = #"key = "${MY_TEST_VAR_S2T}""#
        // Set env var for this test
        setenv("MY_TEST_VAR_S2T", "expanded_value", 1)
        defer { unsetenv("MY_TEST_VAR_S2T") }

        let result = AppConfig.expandEnvironmentVariables(in: input)
        #expect(result == #"key = "expanded_value""#)
    }

    @Test
    func missingEnvironmentVariableExpandsToEmpty() {
        let input = #"key = "${NONEXISTENT_VAR_S2T_TEST}""#
        let result = AppConfig.expandEnvironmentVariables(in: input)
        #expect(result == #"key = """#)
    }

    @Test
    func multipleEnvironmentVariables() {
        setenv("S2T_TEST_A", "alpha", 1)
        setenv("S2T_TEST_B", "beta", 1)
        defer {
            unsetenv("S2T_TEST_A")
            unsetenv("S2T_TEST_B")
        }

        let input = #"first = "${S2T_TEST_A}" and second = "${S2T_TEST_B}""#
        let result = AppConfig.expandEnvironmentVariables(in: input)
        #expect(result == #"first = "alpha" and second = "beta""#)
    }

    @Test
    func emptyApiKeyFailsValidation() {
        let toml = """
        [api]
        openai_key = ""

        [stt]
        model = "gpt-4o-mini-transcribe"
        timeout = 30

        [correction]
        model = "gpt-5-mini"
        timeout = 30

        [tts]
        model = "gpt-4o-mini-tts"
        voice = "coral"
        enabled = true

        [input]
        hotkey = ["left_ctrl", "space"]
        """

        #expect(throws: PipelineError.self) {
            try AppConfig.load(from: toml)
        }
    }

    @Test
    func ttsDisabled() throws {
        let toml = """
        [api]
        openai_key = "sk-test"

        [stt]
        model = "gpt-4o-mini-transcribe"
        timeout = 30

        [correction]
        model = "gpt-5-mini"
        timeout = 30

        [tts]
        model = "gpt-4o-mini-tts"
        voice = "coral"
        enabled = false

        [input]
        hotkey = ["left_ctrl", "space"]
        """
        let config = try AppConfig.load(from: toml)
        #expect(config.tts.enabled == false)
    }
}
