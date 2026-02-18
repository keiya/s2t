@preconcurrency import ApplicationServices
import Carbon
import Foundation
import os

/// Global hotkey detection using CGEventTap.
/// Not @MainActor — CGEventTap callbacks run on a CF run loop thread.
/// Results are dispatched to @MainActor via closures.
final class HotkeyService: Sendable {
    private let keyCode: UInt16
    private let modifierFlags: CGEventFlags

    nonisolated(unsafe) fileprivate var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    let onHotkeyDown: @Sendable @MainActor () -> Void
    let onHotkeyUp: @Sendable @MainActor () -> Void

    init(
        hotkey: [String],
        onHotkeyDown: @escaping @Sendable @MainActor () -> Void,
        onHotkeyUp: @escaping @Sendable @MainActor () -> Void
    ) {
        let parsed = Self.parseHotkey(hotkey)
        self.keyCode = parsed.keyCode
        self.modifierFlags = parsed.flags
        self.onHotkeyDown = onHotkeyDown
        self.onHotkeyUp = onHotkeyUp
    }

    // MARK: - Accessibility Check

    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Start / Stop

    func start() throws {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: hotkeyCallback,
                userInfo: refcon
            )
        else {
            throw PipelineError.configurationError(
                "Failed to create event tap. Grant Accessibility permission in System Settings > Privacy & Security > Accessibility."
            )
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Logger.hotkey.error("Hotkey service started (keyCode=\(self.keyCode, privacy: .public), flags=\(self.modifierFlags.rawValue, privacy: .public))")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        Logger.hotkey.info("Hotkey service stopped")
    }

    // MARK: - Event Handling

    /// Called from the C callback. Returns true if the event was consumed (should be suppressed).
    func handleEvent(_ type: CGEventType, event: CGEvent) -> Bool {
        let currentKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let currentFlags = event.flags

        switch type {
        case .keyDown:
            if currentKeyCode == keyCode && currentFlags.contains(modifierFlags) {
                Task { @MainActor in
                    self.onHotkeyDown()
                }
                return true
            }
        case .keyUp:
            if currentKeyCode == keyCode {
                Task { @MainActor in
                    self.onHotkeyUp()
                }
                return true
            }
        case .flagsChanged:
            break
        default:
            break
        }
        return false
    }

    // MARK: - Hotkey Parsing

    struct ParsedHotkey: Sendable {
        let keyCode: UInt16
        let flags: CGEventFlags
    }

    static func parseHotkey(_ keys: [String]) -> ParsedHotkey {
        var flags = CGEventFlags()
        var keyCode: UInt16 = 0

        for key in keys {
            let lower = key.lowercased()
            if let modifier = modifierLookup[lower] {
                flags.insert(modifier)
            } else if let code = keyCodeLookup[lower] {
                keyCode = code
            } else {
                Logger.hotkey.warning("Unknown hotkey component: \(key)")
            }
        }

        return ParsedHotkey(keyCode: keyCode, flags: flags)
    }

    // MARK: - Lookup Tables

    static let modifierLookup: [String: CGEventFlags] = [
        "left_ctrl": .maskControl,
        "right_ctrl": .maskControl,
        "ctrl": .maskControl,
        "control": .maskControl,
        "left_shift": .maskShift,
        "right_shift": .maskShift,
        "shift": .maskShift,
        "left_alt": .maskAlternate,
        "right_alt": .maskAlternate,
        "alt": .maskAlternate,
        "option": .maskAlternate,
        "left_cmd": .maskCommand,
        "right_cmd": .maskCommand,
        "cmd": .maskCommand,
        "command": .maskCommand,
    ]

    static let keyCodeLookup: [String: UInt16] = [
        "space": UInt16(kVK_Space),
        "return": UInt16(kVK_Return),
        "tab": UInt16(kVK_Tab),
        "escape": UInt16(kVK_Escape),
        "delete": UInt16(kVK_Delete),
        "a": UInt16(kVK_ANSI_A),
        "b": UInt16(kVK_ANSI_B),
        "c": UInt16(kVK_ANSI_C),
        "d": UInt16(kVK_ANSI_D),
        "e": UInt16(kVK_ANSI_E),
        "f": UInt16(kVK_ANSI_F),
        "g": UInt16(kVK_ANSI_G),
        "h": UInt16(kVK_ANSI_H),
        "i": UInt16(kVK_ANSI_I),
        "j": UInt16(kVK_ANSI_J),
        "k": UInt16(kVK_ANSI_K),
        "l": UInt16(kVK_ANSI_L),
        "m": UInt16(kVK_ANSI_M),
        "n": UInt16(kVK_ANSI_N),
        "o": UInt16(kVK_ANSI_O),
        "p": UInt16(kVK_ANSI_P),
        "q": UInt16(kVK_ANSI_Q),
        "r": UInt16(kVK_ANSI_R),
        "s": UInt16(kVK_ANSI_S),
        "t": UInt16(kVK_ANSI_T),
        "u": UInt16(kVK_ANSI_U),
        "v": UInt16(kVK_ANSI_V),
        "w": UInt16(kVK_ANSI_W),
        "x": UInt16(kVK_ANSI_X),
        "y": UInt16(kVK_ANSI_Y),
        "z": UInt16(kVK_ANSI_Z),
        "0": UInt16(kVK_ANSI_0),
        "1": UInt16(kVK_ANSI_1),
        "2": UInt16(kVK_ANSI_2),
        "3": UInt16(kVK_ANSI_3),
        "4": UInt16(kVK_ANSI_4),
        "5": UInt16(kVK_ANSI_5),
        "6": UInt16(kVK_ANSI_6),
        "7": UInt16(kVK_ANSI_7),
        "8": UInt16(kVK_ANSI_8),
        "9": UInt16(kVK_ANSI_9),
        "f1": UInt16(kVK_F1),
        "f2": UInt16(kVK_F2),
        "f3": UInt16(kVK_F3),
        "f4": UInt16(kVK_F4),
        "f5": UInt16(kVK_F5),
        "f6": UInt16(kVK_F6),
        "f7": UInt16(kVK_F7),
        "f8": UInt16(kVK_F8),
        "f9": UInt16(kVK_F9),
        "f10": UInt16(kVK_F10),
        "f11": UInt16(kVK_F11),
        "f12": UInt16(kVK_F12),
    ]
}

// MARK: - C Callback (free function)

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Logger.hotkey.warning("Event tap was disabled, re-enabling")
        let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
        if let tap = service.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
    let consumed = service.handleEvent(type, event: event)

    // Return nil to suppress the event when hotkey is matched
    return consumed ? nil : Unmanaged.passRetained(event)
}
