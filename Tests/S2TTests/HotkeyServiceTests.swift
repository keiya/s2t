import Testing
import Carbon
@testable import S2T

@Suite("HotkeyService tests")
struct HotkeyServiceTests {

    @Test
    func parseSpaceKey() {
        let result = HotkeyService.parseHotkey(["space"])
        #expect(result.keyCode == UInt16(kVK_Space))
        #expect(result.flags == CGEventFlags())
    }

    @Test
    func parseCtrlSpace() {
        let result = HotkeyService.parseHotkey(["left_ctrl", "space"])
        #expect(result.keyCode == UInt16(kVK_Space))
        #expect(result.flags.contains(.maskControl))
    }

    @Test
    func parseCmdShiftA() {
        let result = HotkeyService.parseHotkey(["cmd", "shift", "a"])
        #expect(result.keyCode == UInt16(kVK_ANSI_A))
        #expect(result.flags.contains(.maskCommand))
        #expect(result.flags.contains(.maskShift))
    }

    @Test
    func parseAltF5() {
        let result = HotkeyService.parseHotkey(["alt", "f5"])
        #expect(result.keyCode == UInt16(kVK_F5))
        #expect(result.flags.contains(.maskAlternate))
    }

    @Test
    func parseUnknownKeyIgnored() {
        let result = HotkeyService.parseHotkey(["left_ctrl", "unknown_key"])
        // unknown_key is ignored, keyCode defaults to 0
        #expect(result.flags.contains(.maskControl))
    }

    @Test
    func modifierLookupContainsAllVariants() {
        let modKeys = ["left_ctrl", "right_ctrl", "ctrl", "control",
                       "left_shift", "right_shift", "shift",
                       "left_alt", "right_alt", "alt", "option",
                       "left_cmd", "right_cmd", "cmd", "command"]
        for key in modKeys {
            #expect(HotkeyService.modifierLookup[key] != nil, "Missing modifier: \(key)")
        }
    }

    @Test
    func keyCodeLookupContainsLetters() {
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            #expect(
                HotkeyService.keyCodeLookup[String(letter)] != nil,
                "Missing key: \(letter)"
            )
        }
    }
}
