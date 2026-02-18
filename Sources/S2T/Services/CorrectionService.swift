import Foundation
import os

protocol CorrectionService: Sendable {
    func correct(transcript: String) async throws -> CorrectionResult
}

struct OpenAICorrectionService: CorrectionService {
    let apiKey: String
    let model: String
    let timeout: TimeInterval

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let maxRetries = 1

    func correct(transcript: String) async throws -> CorrectionResult {
        var lastError: (any Error)?

        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                Logger.correction.info("Retrying correction (attempt \(attempt + 1))")
            }

            do {
                return try await performCorrection(transcript: transcript)
            } catch let error as DecodingError {
                Logger.correction.warning("JSON parse failed (attempt \(attempt + 1)): \(error.localizedDescription)")
                lastError = error
            } catch {
                throw error
            }
        }

        throw PipelineError.correctionFailed(
            underlying: "JSON parsing failed after \(Self.maxRetries + 1) attempts: \(lastError?.localizedDescription ?? "unknown")"
        )
    }

    private func performCorrection(transcript: String) async throws -> CorrectionResult {
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: transcript),
            ],
            responseFormat: .init(
                type: "json_schema",
                jsonSchema: .init(
                    name: "correction_result",
                    strict: true,
                    schema: Self.correctionSchema
                )
            )
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        Logger.correction.info("Sending correction request")

        let (data, response) = try await URLSession.shared.upload(for: request, from: bodyData)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PipelineError.networkError(underlying: "Invalid response")
        }

        try Self.checkHTTPStatus(httpResponse, data: data)

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw PipelineError.correctionFailed(underlying: "Empty response from LLM")
        }

        let contentData = Data(content.utf8)
        let result = try JSONDecoder().decode(CorrectionResult.self, from: contentData)

        Logger.correction.info("Correction complete: \(result.issues.count) issues found")
        return result
    }

    private static func checkHTTPStatus(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200: return
        case 401:
            throw PipelineError.authenticationError
        case 429:
            throw PipelineError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw PipelineError.correctionFailed(
                underlying: "HTTP \(response.statusCode): \(body)"
            )
        }
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    You are an English language correction assistant. Analyze the transcribed English text and correct any grammar, vocabulary, or naturalness issues.

    Rules:
    - Fix grammar errors (subject-verb agreement, tense, articles, prepositions, etc.)
    - Fix vocabulary issues (wrong word choice, unnatural phrasing)
    - Keep corrections minimal — don't rewrite the entire sentence if only one word is wrong
    - The "span" should reference character positions in the ORIGINAL text
    - "severity" must be one of: "low", "medium", "high"
    - If the text is already correct, return it as-is with an empty issues array
    - "reason" should be a brief explanation in English
    - "note" is optional additional context for the learner
    """

    // MARK: - JSON Schema for Structured Output

    static let correctionSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "corrected_text": .object([
                "type": .string("string"),
            ]),
            "issues": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "span": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "start": .object(["type": .string("integer")]),
                                "end": .object(["type": .string("integer")]),
                            ]),
                            "required": .array([.string("start"), .string("end")]),
                            "additionalProperties": .bool(false),
                        ]),
                        "original": .object(["type": .string("string")]),
                        "corrected": .object(["type": .string("string")]),
                        "reason": .object(["type": .string("string")]),
                        "severity": .object([
                            "type": .string("string"),
                            "enum": .array([.string("low"), .string("medium"), .string("high")]),
                        ]),
                        "note": .object([
                            "type": .array([.string("string"), .string("null")]),
                        ]),
                    ]),
                    "required": .array([
                        .string("span"), .string("original"), .string("corrected"),
                        .string("reason"), .string("severity"), .string("note"),
                    ]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ]),
        "required": .array([.string("corrected_text"), .string("issues")]),
        "additionalProperties": .bool(false),
    ])
}

// MARK: - Chat Completion API Types

private struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Codable {
    let type: String
    let jsonSchema: JSONSchemaRef

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct JSONSchemaRef: Codable {
    let name: String
    let strict: Bool
    let schema: JSONSchemaValue
}

/// Recursive JSON schema value for encoding arbitrary JSON structures.
enum JSONSchemaValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONSchemaValue])
    case object([String: JSONSchemaValue])

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .int(let i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for item in a { try c.encode(item) }
        case .object(let o):
            var c = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in o.sorted(by: { $0.key < $1.key }) {
                try c.encode(value, forKey: DynamicCodingKey(key))
            }
        }
    }

    init(from decoder: any Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        }
        if var c = try? decoder.unkeyedContainer() {
            var arr: [JSONSchemaValue] = []
            while !c.isAtEnd { arr.append(try c.decode(JSONSchemaValue.self)) }
            self = .array(arr); return
        }
        if let c = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: JSONSchemaValue] = [:]
            for key in c.allKeys { dict[key.stringValue] = try c.decode(JSONSchemaValue.self, forKey: key) }
            self = .object(dict); return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Cannot decode JSONSchemaValue"))
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private struct ChatCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: ChoiceMessage
    }

    struct ChoiceMessage: Codable {
        let content: String?
    }
}
