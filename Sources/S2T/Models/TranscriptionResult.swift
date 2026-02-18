struct TranscriptionResult: Sendable, Codable, Equatable {
    let text: String
    let detectedLanguage: String?

    enum CodingKeys: String, CodingKey {
        case text
        case detectedLanguage = "detected_language"
    }
}
