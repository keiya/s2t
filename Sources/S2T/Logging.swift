import os

extension Logger {
    private static let subsystem = "org.keiya.s2t"

    static let stt = Logger(subsystem: subsystem, category: "stt")
    static let correction = Logger(subsystem: subsystem, category: "correction")
    static let tts = Logger(subsystem: subsystem, category: "tts")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
}
