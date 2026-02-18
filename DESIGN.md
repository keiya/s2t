# 語学学習（英語学習）STT Mac アプリ MVP 設計書

## 1. 概要

### 1.1 目的
- macOS 上で音声入力（Speech-to-Text）を実行し、英語の文字起こし結果を表示する。
- STT 結果を LLM で校正し、誤り箇所・修正文・理由を画面表示する。
- 校正完了時に修正文を自動でクリップボードにコピーし、ユーザーは任意のアプリで `⌘V` で貼り付ける。
- 校正完了時に修正文を `gpt-4o-mini-tts` で自動再生し、正しい発音を提示する。
- **入力注入は行わない**。テキストは自アプリのウィンドウ内に表示するのみ。

### 1.2 対象範囲（MVP）
- OS: macOS（Apple Silicon）
- 音源: デスクトップマイク
- STT: `gpt-4o-mini-transcribe` 固定（フェイルオーバーなし）
- 校正: `gpt-5-mini`
- TTS: `gpt-4o-mini-tts`
- 対象言語: 英語のみ（母語バイパス判定は実装しない）

### 1.3 MVP で明示的に実装しないもの
- アプリへの直接テキスト注入（Accessibility API / イベント注入）
- Say Again フロー（undo + 再録音）
- 母語バイパス判定（`LanguageClassifier`）
- STT モデルのフェイルオーバー切替
- 学習ログ（JSONL 記録・retention）
- ホットキーモード `toggle`（Push-to-Talk のみ）
- GUI 設定画面

### 1.4 用語
- **Transcription Result**: STT が返す生文字起こし
- **Correction Result**: LLM 校正後の結果（修正文 + issues）

---

## 2. 設計方針

### 2.1 言語方針
- 英語専用。STT 呼び出し言語は `en-US` 固定。
- 日本語で話した場合は不正確な英語文字起こしが返るが、MVP では許容する。

### 2.2 設定方針（TOML 固定）
- 起動時に TOML を 1 本読み込み。実行中の hot reload は実装しない。
- 設定 UI は持たない。変更反映は再起動。
- 想定パス: `~/Library/Application Support/org.keiya.s2t/config.toml`

### 2.3 コア設計思想
- STT と校正はサービスとして分離し、モデル・タイムアウトを設定から注入可能にする。
- **入力注入を排除**し、クリップボード経由でユーザーに制御を委ねる。
- 校正完了時は修正文を自動クリップボードコピー + TTS 自動再生。校正失敗時は生文字起こしをコピー（TTS なし）。

---

## 3. 機能要件

### 3.1 Must（必須）
1. グローバルホットキーによる Push-to-Talk 録音（押して話す）
2. 録音音声を `gpt-4o-mini-transcribe`（`en-US`）で文字起こし
3. 文字起こし結果を `gpt-5-mini` で校正し、画面に以下を表示
   - 生文字起こし（原文）
   - 修正後テキスト
   - 誤り箇所ごとの詳細（元の語、修正語、理由、修正信頼度）
4. 校正完了時に修正文を自動でクリップボードにコピー
5. 校正完了時に修正文を `gpt-4o-mini-tts` で自動再生（設定でオフ可能）
6. 生文字起こしは UI 上のクリックまたはショートカットでクリップボードにコピー可能
7. 校正失敗時は生文字起こしを自動クリップボードコピーにフォールバック（TTS は実行しない）
8. エラー時（認識失敗・通信失敗）はエラー表示

### 3.2 Should（将来追加）
1. アプリへの直接テキスト注入（Accessibility API）
2. Say Again フロー（undo + 再録音）
3. 母語バイパス判定
4. STT モデルフェイルオーバー
5. 修正前後比較ハイライト
6. 学習ログ記録・傾向分析
7. 学習目的プリセット（会話英語/ビジネス英語/試験対策）

---

## 4. システムアーキテクチャ

### 4.1 レイヤ
1. **UI Layer** — 録音コントロール、校正結果表示
2. **Audio Input Layer** — 録音バッファ、無音終了/長さ制御
3. **STT Layer** — OpenAI トランスクリプション呼び出し
4. **Correction Layer** — LLM 校正、構造化理由付与
5. **TTS Layer** — 修正文の音声合成・再生
6. **Clipboard Layer** — 修正文/生文字起こしのクリップボード操作

### 4.2 データフロー
```text
音声入力
  → 録音バッファ
    → STT API（en-US 固定）
      → 生文字起こし
        → UI に表示
        → LLM 校正（gpt-5-mini）
          → 成功: 修正文 + issues を UI 表示
                   修正文をクリップボードへ
                   修正文を TTS で自動再生（並行）
          → 失敗: 生文字起こしをクリップボードへ
```

---

## 5. 詳細設計

### 5.1 コンポーネント構成

#### Controller 層
- `RecordingCoordinator` — 録音状態管理
- `PipelineOrchestrator` — `STT → 校正 → UI → クリップボード` の実行制御

#### Service 層
- `SpeechService` — 音声キャプチャ（AVAudioEngine）
- `TranscriptionService` — OpenAI API 呼び出し
- `CorrectionService` — gpt-5-mini 呼び出し
- `TTSService` — gpt-4o-mini-tts 呼び出し + AVAudioPlayer 再生
- `ClipboardService` — NSPasteboard 操作

#### Data 層
- `AppConfig` — TOML 設定読み込み

### 5.2 状態遷移

```text
IDLE → RECORDING → PROCESSING → DONE
                                  ↓
                                ERROR
```

- `IDLE`: 待機（ホットキー監視中）
- `RECORDING`: 音声収集中
- `PROCESSING`: STT + 校正呼び出し中
- `DONE`: 結果表示完了（クリップボードコピー済み）
- `ERROR`: 失敗（エラー表示、生文字起こしがあればクリップボードへ）

`DONE` / `ERROR` からは次のホットキー押下で `RECORDING` へ遷移。

### 5.3 処理フロー

1. ユーザーがホットキーを押下して録音開始
2. ホットキーを離して録音終了（または無音検出/最大長で自動終了）
3. `TranscriptionService.transcribe()` 呼び出し
4. 生文字起こしを UI に即時表示
5. `CorrectionService.correct()` 呼び出し
6. 校正成功時:
   - 修正文 + issues を UI に表示
   - 修正文をクリップボードに自動コピー
   - 修正文を `TTSService` で音声合成し自動再生（クリップボードコピーと並行）
7. 校正失敗時:
   - 生文字起こしをクリップボードに自動コピー
   - TTS は実行しない
   - エラー表示
8. ユーザーは任意のアプリで `⌘V` で貼り付け

---

## 6. インターフェース仕様

### 6.1 `TranscriptionService`
- `transcribe(audioData: Data) async throws -> TranscriptionResult`
- パラメータ:
  - `model`: 設定から注入（MVP では `gpt-4o-mini-transcribe` 固定）
  - `language`: `en-US` 固定
  - `timeout`: 設定から注入
- 戻り値:
  ```
  TranscriptionResult {
    text: String
    detected_language: String?  // API が返す場合
  }
  ```
- 失敗時は `throw`。呼び出し元でエラーハンドリング。

### 6.2 `CorrectionService`
- `correct(transcript: String) async throws -> CorrectionResult`
- LLM プロンプトで以下を指示:
  - 入力テキストの文法・語法・自然さを校正
  - 構造化 JSON で返却
- 出力 JSON スキーマ:
```json
{
  "corrected_text": "...",
  "issues": [
    {
      "span": { "start": 0, "end": 5 },
      "original": "I has",
      "corrected": "I have",
      "reason": "主語と動詞の一致",
      "severity": "high",
      "note": "三人称単数以外の主語には have を使用"
    }
  ]
}
```
- `severity` は `"low"` / `"medium"` / `"high"` の enum。
- JSON パース失敗時は 1 回リトライ。2 回目失敗で `throw`（呼び出し元が生文字起こしフォールバック）。

### 6.3 `TTSService`
- `speak(text: String) async throws`
- 校正完了時に `PipelineOrchestrator` から呼び出し。クリップボードコピーとは並行で実行。
- パラメータ:
  - `model`: 設定から注入（MVP では `gpt-4o-mini-tts` 固定）
  - `voice`: 設定から注入（既定: `coral`）
- 処理:
  1. OpenAI TTS API を呼び出し、音声データ（mp3/opus）を取得
  2. `AVAudioPlayer` で即時再生
- TTS 失敗時は音声なしで続行（エラーは軽微扱い、UI にも通知しない）。
- 新しい録音が開始されたら再生中の音声は即停止。

### 6.4 `ClipboardService`
- `copyToClipboard(text: String)`
- NSPasteboard を使用。
- 校正完了時に修正文を自動コピー。
- 校正失敗時に生文字起こしを自動コピー。
- UI 上の操作で生文字起こしをコピーする機能も提供。

---

## 7. 設定（TOML）

### 7.1 最小キー
```toml
[api]
openai_key = "${OPENAI_API_KEY}"

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
```

### 7.2 設定検証ルール
- 型チェック（string / list）
- `api.openai_key` 未設定時は起動エラー
- その他キー欠損時は既定値注入

---

## 8. エラーハンドリング

| 分類 | 方針 |
|---|---|
| 認識失敗（無音/短尺/通信） | エラー表示。クリップボード操作なし |
| LLM 校正失敗 | 生文字起こしをクリップボードにコピー、エラー表示 |
| 不正 JSON | 1 回リトライ。2 回目失敗で生文字起こしフォールバック |
| TTS 失敗 | 音声なしで続行（軽微エラー扱い、UI 通知なし） |
| クリップボード操作失敗 | エラー表示（UI 上にテキストは残っている） |

---

## 9. UI/UX 設計

### 9.1 表示構成
- **メインエリア**: 修正文（校正完了時）または生文字起こし（校正中/失敗時）
- **補助パネル**:
  - 生文字起こし（原文）— クリックでクリップボードにコピー
  - 誤り一覧（original → corrected、理由、severity）
- **ステータス表示**: 録音中 / 処理中 / 完了 / エラー
- **クリップボード通知**: コピー完了時に小さなフィードバック表示
- **再生ボタン**: 修正文の TTS 音声をリプレイ（自動再生後に再度聞きたい場合）

### 9.2 操作
- ホットキー押下: 録音開始（TTS 再生中なら即停止）
- ホットキー離す: 録音終了 → 自動で STT + 校正 + TTS 実行
- 生文字起こしクリック: 生文字起こしをクリップボードにコピー
- 校正完了時は修正文が自動でクリップボードに入るので、ユーザーは `⌘V` で任意のアプリに貼り付け

---

## 10. 観測・評価指標（MVP）
- 録音終了 → 生文字起こし表示までの平均レイテンシ
- 録音終了 → 校正完了（クリップボードコピー）までの平均レイテンシ
- 録音終了 → TTS 再生開始までの平均レイテンシ
- 校正失敗率
- 1 日あたりの API コール数とコスト

---

## 11. 実装フェーズ

### MVP（本設計書の範囲）
- 録音 + STT + 校正 + UI 表示 + クリップボード自動コピー + 修正文 TTS 自動再生

### Post-MVP
1. **入力注入**: Accessibility API でアプリへ直接注入
2. **母語バイパス**: `LanguageClassifier` 導入、日本語発話時は校正スキップ
3. **Say Again**: undo + 再録音フロー
4. **STT フェイルオーバー**: `gpt-4o-transcribe` への自動切替
5. **学習ログ**: JSONL 記録、誤り傾向集計
6. **UI 強化**: 修正前後ハイライト、学習目的プリセット

---

## 12. 重要意思決定（実装前の未確定項目）
1. macOS 配信形態: ネイティブ Swift を優先（現時点）
2. `gpt-5-mini` 応答 JSON スキーマの severity を enum 固定にする（`low` / `medium` / `high`）
3. 短い発話（"yes", "okay" 等）の校正スキップ閾値を設けるか → MVP では設けない、コスト観測後に判断

---

## 13. リスクと補足
- 無音判定と短尺判定の閾値設計が認識率に直接影響するため、初期値を設定し観測ベースで調整。
- LLM 出力 JSON の厳密性確保は、サニタイズ + 1 回リトライ + 生文字起こしフォールバックの構成。
- 日本語で話した場合の挙動が不自然になるが、MVP では許容。Post-MVP で母語バイパスを導入。
- API コストは 1 発話あたり STT + 校正 + TTS の 3 回コール。日常利用で積み上がるため、早期にコスト観測指標を確認する。