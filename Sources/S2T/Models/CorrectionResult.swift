struct CorrectionResult: Sendable, Codable, Equatable {
    let correctedText: String
    let issues: [CorrectionIssue]

    enum CodingKeys: String, CodingKey {
        case correctedText = "corrected_text"
        case issues
    }
}

struct CorrectionIssue: Sendable, Codable, Equatable {
    let span: TextSpan
    let original: String
    let corrected: String
    let reason: String
    let severity: Severity
    let note: String?
}

struct TextSpan: Sendable, Codable, Equatable {
    let start: Int
    let end: Int
}

enum Severity: String, Sendable, Codable, Equatable {
    case low
    case medium
    case high
}
