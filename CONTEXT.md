# Hushword Context

## Domain Language

- **Dictation Session** — one `Fn` start, microphone capture, one `Fn` stop, finalization, and automatic insertion.
- **Whole Recording** — the complete local WAV captured before either recognizer starts.
- **Final Transcript** — the selected text after Apple and Whisper recognize the same Whole Recording.
- **Dictation Context** — manual replacements, Correction Memory, and terminology hints shared by Apple, Whisper, and transcript cleaning.
- **Recognition Evidence** — text, confidence, alternatives, and timing returned directly by Apple or Whisper.
- **Correction Memory** — local, user-confirmed spelling preferences; manual entries outrank automatically observed corrections.
- **Terminology Hint** — a repeated technical term from local history that may bias recognition but can never replace transcript text.
- **Paste Target** — the last regular external application selected before a Dictation Session and locked until insertion completes.
- **Presentation Snapshot** — the consistent recording flag, HUD phase, and microphone level published to AppKit.
- **Local Model Server** — a supervised loopback HTTP process whose lifecycle is owned by Hushword.
- **Whisper Asset** — the pinned Q5 model downloaded to Application Support and accepted only after byte-count and SHA-256 verification.
- **Whisper Runtime** — the self-contained, chip-selected `whisper.cpp` server bundled inside the app.

## Module Map

```text
Fn / Option-Space
       |
       v
   AppModel ---------------------> PasteTargetTracker
       |                                  |
       |                                  v
       |                             TextInserter
       v
 DictationEngine
       |
       v
 Speech Capture
   |
   +---- Complete local WAV
   |
   +---- Apple whole-recording recognition
   |
   +---- Whisper whole-recording recognition

Whisper adapter
       |
       v
LocalHTTPServerProcess
```

## Architecture Rules

- `AppModel` owns user-visible state and persisted history/settings. It must not implement recognition, model-process, or workspace-notification details.
- `DictationEngine` owns start/finish orchestration and lightweight Apple/Whisper candidate selection.
- `SpeechRecognitionService` is intentionally a deep module. Its interface is `start`, `stop`, and `shutdown`; Apple backend and audio-file details stay inside it.
- `LocalHTTPServerProcess` is the only module that starts, health-checks, supervises, or terminates persistent local HTTP processes.
- `WhisperModelManager` owns background Q5 preparation and user-visible model state. Apple recognition must remain usable in every non-ready state.
- `WhisperRuntimeLocator` selects the bundled M1, M2/M3, or M4 static runtime before considering development-only Homebrew paths.
- `PasteTargetTracker` is the only module that observes `NSWorkspace` to select and lock the Paste Target.
- `DictationPresentation` is the only value AppKit uses to synchronize the menu-bar icon and HUD.
- Local development keeps the designated requirement `com.local.hushword`;
  customer releases inject one permanent, owned bundle identifier and must
  never change it after public distribution.
- Normal dictation has no automatic Qwen adapter. Any future local polish path requires measured quality and resource validation before implementation.
- Q8 and Qwen must not be required for the default install.
- Recognition must not run on streaming fragments while recording. Apple and Whisper start only after stop and receive the same complete WAV.
- Recognition Evidence is immutable. Candidate selection may choose only text returned by a recognizer; it must not synthesize words.
- Internal sentence boundaries come from the selected recognizer. A pause alone must never create or upgrade punctuation.
- Punctuation may transfer from Apple to Whisper only when their wording aligns closely; transferred punctuation must not replace words.
- Terminology Hints come only from repeated distinctive terms in local history. They influence recognition prompts but never rewrite text.
- Correction Memory comes only from a direct, stable user edit inside the just-pasted range. It stores narrow spelling preferences locally; manual dictionary entries always win.
- Transcript cleanup may remove explicit fillers, repetitions, and spoken formatting commands, then normalize surface formatting. It must not infer new semantic content.
- Refactors must preserve sentence endings, `Fn` toggle behavior, automatic paste, mixed Chinese-English terminology, real microphone waveform, and reasonable stop-to-paste latency.

## Verification

```bash
swift run HushwordCoreTests
swift run HushwordAppKitTests
swift build -c release --product Hushword
./scripts/install.sh
```
