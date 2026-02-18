# CLAUDE.md — STT English Learning App (macOS)

## Project Overview

macOS native app for English learning via Speech-to-Text with LLM correction and TTS playback.
Swift 6.2 / SwiftUI / macOS 15+ (Apple Silicon).

## Build & Run

```bash
# Build
swift build

# Run
swift run S2T

# Test
swift test

# Build release
swift build -c release
```

Xcode project は使わない。Swift Package Manager のみ。

## Swift Version & Language Mode

- Swift 6.2, language mode `swift6`
- Package.swift に `swiftLanguageMode: [.v6]` を明示
- strict concurrency はデフォルトで有効。`@unchecked Sendable` や `nonisolated(unsafe)` は最終手段

## Architecture Rules

### Concurrency Model

- **`@MainActor` をデフォルトに使え。** UI 層、状態管理、`PipelineOrchestrator` は `@MainActor`。
- **Service 層は `@MainActor` にしない。** UI 更新は呼び出し側（`@MainActor` の Orchestrator）で行う。
- **Audio I/O と TTS 再生は class で実装し、`@MainActor` に置くな。** `SpeechService`（AVAudioEngine）と `TTSService`（AVAudioPlayer）はリアルタイムオーディオスレッドのコールバックが絡むため、actor にもしない（actor hop のオーバーヘッドを避ける）。結果だけ `@MainActor` に返す。
- `@concurrent` は必要な箇所のみ（音声エンコード等）。大半のコードは `@MainActor` か Service 層の素の async で足りる。
- `DispatchQueue` は使うな。全て structured concurrency (`async/await`, `Task`, `TaskGroup`) で書く。
- `Task.detached` は原則禁止。`Task {}` は `@MainActor` コンテキストを継承する。
- `Combine` は使うな。`AsyncSequence` / `Observations` で代替。
- Actor 間のデータ受け渡しは `Sendable` な値型（struct/enum）で行う。

```swift
// ✅ Good: @MainActor for state & orchestration
@MainActor
@Observable
final class PipelineOrchestrator {
    var state: PipelineState = .idle
    private var currentTask: Task<Void, Never>?

    func run(audio: Data) {  // sync — ホットキーから直接呼べる
        currentTask?.cancel()
        currentTask = Task {
            state = .processing(step: .transcribing)
            let transcript = try await transcriptionService.transcribe(audio)
            state = .done(transcript, nil)
        }
    }
}

// ✅ Good: Service is not @MainActor (plain struct)
struct OpenAITranscriptionService: TranscriptionService {
    func transcribe(_ audio: Data) async throws -> TranscriptionResult { ... }
}

// ✅ Good: Audio service is class, not @MainActor, not actor
final class SpeechService {  // class — AVAudioEngine callback are realtime thread
    func startRecording() throws { ... }
    func stopRecording() -> Data { ... }
}

// ❌ Bad
DispatchQueue.global().async { ... }
Task.detached { ... }
```

### State Management

- `@Observable` マクロを使え（`ObservableObject` / `@Published` / `Combine` は使うな）。
- View の状態は `@State` で `@Observable` オブジェクトを保持。
- View 間の受け渡しは `@Environment` か直接引数。`@EnvironmentObject` は使うな。
- `@Bindable` は View が `@Observable` オブジェクトへの binding を作る時に使う。

```swift
// ✅ Good
@Observable
final class AppState {
    var pipelineState: PipelineState = .idle
    var transcript: String = ""
    var correction: CorrectionResult?
}

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        RecordingView(state: appState)
    }
}

// ❌ Bad: legacy pattern
class AppState: ObservableObject {
    @Published var transcript: String = ""
}
```

### Data Types

- Model は全て `struct` か `enum`。`class` は `@Observable` な状態オブジェクトだけ。
- API レスポンスの decode は `Codable` struct で。手動 JSON パースはしない。
- Error 型は `enum` で定義し、`LocalizedError` に準拠。
- Optional は状態表現（未取得、未完了）には自然に使ってよい（例: `CorrectionResult?`）。モデル層では慎重に — API 仕様に引きずられて Optional だらけにしない。

```swift
// ✅ Good
struct TranscriptionResult: Sendable {
    let text: String
    let detectedLanguage: String?
}

enum PipelineState: Sendable {
    case idle
    case recording
    case processing(step: ProcessingStep)
    case done(TranscriptionResult, CorrectionResult?)
    case error(PipelineError)
}

enum ProcessingStep: Sendable {
    case transcribing
    case correcting
    case speaking
}
```

### Error Handling

- `Result` 型は使うな。`throws` / `async throws` を使え。
- `do-catch` は呼び出し側で。Service 層は throw するだけ。
- `try!` / `try?` は原則禁止。`try?` は明示的にログする場合のみ。
- **タイムアウト**: 全 API 呼び出しに設定値ベースのタイムアウトを設ける。
- **リトライ**: LLM の JSON パース失敗時は 1 回だけリトライ。2 回目失敗で生文字起こしフォールバック。
- **エラー表示**: 認識失敗・通信失敗・認証エラーは全て UI に明示。

### Pipeline Rules

- **キャンセル可能**: 新しい録音が開始されたら、実行中のパイプライン Task を即 cancel する。
- **多重起動ガード**: 同時に複数の Pipeline を走らせない。state machine で `recording` / `processing` 中は新規 run をブロックまたは前回を cancel してから開始。
- **TTS 再生中に新規録音**: 再生を即停止し、録音を開始。

```swift
// ✅ Pipeline cancel pattern (run() is sync, Task managed internally)
@MainActor
@Observable
final class PipelineOrchestrator {
    var state: PipelineState = .idle
    private var currentTask: Task<Void, Never>?

    func run(audio: Data) {
        currentTask?.cancel()
        currentTask = Task {
            guard !Task.isCancelled else { return }
            state = .processing(step: .transcribing)
            // ...
        }
    }
}
```

```swift
// ✅ Good
func transcribe(_ audio: Data) async throws(TranscriptionError) -> TranscriptionResult {
    guard audio.count > minAudioSize else {
        throw .tooShort
    }
    // ...
}

// ❌ Bad
func transcribe(_ audio: Data) async -> Result<TranscriptionResult, Error> { ... }
```

### Service Layer

- Service は `protocol` で定義し、実装は struct（状態なし）または actor（状態あり）。
- 依存性は init 注入。Service Locator / singleton は使うな。
- HTTP 通信は `URLSession.shared` の async メソッドを直接使え。Alamofire 等は不要。

```swift
// ✅ Good
protocol TranscriptionService: Sendable {
    func transcribe(_ audio: Data) async throws -> TranscriptionResult
}

struct OpenAITranscriptionService: TranscriptionService {
    let apiKey: String
    let model: String
    let timeout: TimeInterval

    func transcribe(_ audio: Data) async throws -> TranscriptionResult {
        var request = URLRequest(url: endpoint)
        // ...
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        return try JSONDecoder().decode(TranscriptionResult.self, from: data)
    }
}
```

## File Structure

```
Package.swift
Sources/
  S2T/
    App.swift                    # @main, SwiftUI App entry
    Config/
      AppConfig.swift            # TOML 設定読み込み
    Models/
      TranscriptionResult.swift
      CorrectionResult.swift
      PipelineState.swift
    Services/
      SpeechService.swift        # AVAudioEngine recording
      TranscriptionService.swift # OpenAI STT
      CorrectionService.swift    # OpenAI LLM
      TTSService.swift           # OpenAI TTS + AVAudioPlayer
      ClipboardService.swift     # NSPasteboard
      HotkeyService.swift        # CGEventTap
    Orchestration/
      PipelineOrchestrator.swift # STT → Correction → TTS → Clipboard
    Views/
      ContentView.swift
      TranscriptView.swift
      CorrectionPanelView.swift
      StatusIndicator.swift
Tests/
  S2TTests/
    ...
```

## SwiftUI Rules

- View の body は短く保て。50行超えたら子 View に分割。
- View 内にビジネスロジックを書くな。`@Observable` オブジェクトに移せ。
- Preview は主要画面（録音画面、結果表示、修正パネル）に必須。小部品は任意。
- `padding()`, `frame()` 等の modifier は末尾にまとめず、意味単位でグループ化。
- macOS では `.windowStyle(.hiddenTitleBar)` や `.windowResizability(.contentSize)` を活用。

```swift
// ✅ Good: small, focused views
struct CorrectionPanelView: View {
    let correction: CorrectionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(correction.correctedText)
                .font(.body)
            ForEach(correction.issues, id: \.span.start) { issue in
                IssueRow(issue: issue)
            }
        }
    }
}
```

## Naming Conventions

- Types: `UpperCamelCase`
- Functions/properties: `lowerCamelCase`
- Bool は `is` / `has` / `should` prefix: `isRecording`, `hasCorrection`
- 略語は先頭以外小文字: `apiKey`, `ttsService`, `sttModel` (全大文字にしない)
- ファイル名は型名と一致: `PipelineOrchestrator.swift`

## Dependencies

最小限に保つ。正当な理由なく追加しない。

- `TOMLDecoder` — TOML パース（これだけは外部依存が必要）
- Apple frameworks のみ: `SwiftUI`, `AVFoundation`, `ApplicationServices`, `Carbon`（hotkey用）

## Testing

- Service 層は protocol 化してモックテスト可能に。
- `async` テストは `Swift Testing` フレームワーク（`@Test` マクロ）を使え。XCTest は使うな。

```swift
// ✅ Good: Swift Testing
import Testing

@Test
func transcriptionDecodesCorrectly() async throws {
    let service = MockTranscriptionService(result: .init(text: "hello", detectedLanguage: "en"))
    let result = try await service.transcribe(Data())
    #expect(result.text == "hello")
}
```

## Things to Avoid

- `Combine` — 使うな。`AsyncSequence` で代替。
- `ObservableObject` / `@Published` — 使うな。`@Observable` で代替。
- `@StateObject` / `@ObservedObject` — 使うな。`@State` + `@Observable` で代替。
- `@EnvironmentObject` — 使うな。`@Environment` で代替。
- `DispatchQueue` — 使うな。`async/await` で代替。
- `Alamofire` / `Moya` — 使うな。`URLSession` で十分。
- `SwiftyJSON` — 使うな。`Codable` で十分。
- `Result` 型 — 使うな。`throws` で十分。
- `Any` / `AnyObject` — 原則使うな。具体型かジェネリクスで。
- Force unwrap (`!`) — 原則禁止。
- Implicitly unwrapped optionals (`String!`) — IBOutlet 以外禁止（そもそも IBOutlet は使わない）。
- `class` の継承階層 — 使うな。protocol + struct/enum で構成。
- `@objc` — `CGEventTap` のコールバック等、C API bridging でのみ許可。
- `print()` デバッグ — 使うな。`os.Logger` を使え。

## Logging

**API キー・認証情報は絶対にログに出すな。**

```swift
import os

extension Logger {
    static let stt = Logger(subsystem: "org.keiya.s2t", category: "stt")
    static let correction = Logger(subsystem: "org.keiya.s2t", category: "correction")
    static let tts = Logger(subsystem: "org.keiya.s2t", category: "tts")
    static let audio = Logger(subsystem: "org.keiya.s2t", category: "audio")
}

// Usage
Logger.stt.info("Transcription started")
Logger.stt.error("API failed: \(error.localizedDescription)")

// ✅ Good: sensitive data marked private
Logger.stt.debug("Request to \(endpoint, privacy: .private)")

// ❌ Bad: API key in logs
Logger.stt.info("Key: \(apiKey)")
```

- `privacy: .private` を機密情報に付ける。
- API リクエスト/レスポンスの生ボディをログに出さない。

## Git

- コミットメッセージは英語、conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- 1 commit = 1 logical change