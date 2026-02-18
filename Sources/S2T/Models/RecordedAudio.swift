import Foundation

struct RecordedAudio: Sendable {
    let data: Data
    let filename: String
    let contentType: String
}
