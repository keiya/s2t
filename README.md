# S2T — Speech-to-Text English Learning App

macOS native app that helps you practice English speaking. Record your voice, get instant grammar corrections, and hear the corrected version read back to you.

## How It Works

1. **Hold the hotkey** to record yourself speaking English
2. **Release** to trigger the pipeline:
   - Your speech is transcribed (OpenAI Whisper)
   - The transcript is checked for grammar, vocabulary, and naturalness (OpenAI LLM)
   - Corrections are displayed with explanations and severity levels
   - The corrected text is read aloud (OpenAI TTS)
   - The corrected text is copied to your clipboard

If correction fails, the raw transcript is copied instead. TTS failure is non-critical and won't block the pipeline.

## Requirements

- macOS 15+ (Apple Silicon)
- Swift 6.2
- OpenAI API key

## Setup

### 1. Build & Run

```bash
swift build
swift run S2T
```

### 2. Configuration

On first launch, a config file is created at:

```
~/Library/Application Support/org.keiya.s2t/config.toml
```

Edit it with your OpenAI API key:

```toml
[api]
openai_key = "${OPENAI_API_KEY}"   # Environment variable, or paste the key directly

[stt]
model = "gpt-4o-mini-transcribe"
timeout = 30

[correction]
model = "gpt-5-mini"
timeout = 30

[tts]
model = "gpt-4o-mini-tts"
voice = "coral"                    # OpenAI TTS voice
enabled = true                     # Set false to disable TTS

[input]
hotkey = ["left_ctrl", "space"]    # Global hotkey combination
```

You can use `${ENV_VAR}` syntax to reference environment variables. Changes require an app restart.

### 3. Permissions

Since the app runs via `swift run` (not as a .app bundle), permissions are tied to your **terminal app** (Terminal.app, iTerm2, Warp, etc.). Grant both in **System Settings > Privacy & Security**:

- **Microphone** — grant to your terminal app. Without this, recording captures silence.
- **Accessibility** — grant to your terminal app. Without this, the global hotkey won't work.

## Hotkey

Default: **Left Control + Space**

Configurable in `config.toml` as an array of key names:

```toml
hotkey = ["left_ctrl", "space"]
```

Available modifiers: `left_ctrl`, `right_ctrl`, `shift`, `alt` / `option`, `cmd` / `command`

Available keys: `space`, `return`, `a`–`z`, `0`–`9`, `f1`–`f12`, etc.

### Behavior

| Action | Result |
|---|---|
| Press & hold hotkey | Start recording |
| Release hotkey | Stop recording, run pipeline |
| Press hotkey during TTS playback | Stop playback, start new recording |

## UI

The window shows:

- **Status bar** — current state (Ready / Recording / Transcribing / Correcting / Speaking / Done / Error) with a level meter during recording and a "Copied!" indicator
- **Transcript** — the corrected text (or raw transcript if correction failed)
- **Correction panel** — lists each issue found:
  - Original text (strikethrough) and corrected version
  - Reason for correction
  - Severity badge (LOW / MEDIUM / HIGH)
  - Optional learner note
- **Buttons** — Copy raw transcript, Replay TTS

## Cost

Each utterance makes 3 OpenAI API calls (STT + correction + TTS). Cost scales with usage frequency and transcript length.
