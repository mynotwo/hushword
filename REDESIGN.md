# Redesign

## What Hushword is for

Private push-to-talk dictation for Apple Silicon Macs, aimed at people who write
mixed Chinese-English technical text. Tap `Fn`, speak, tap `Fn`, and the
transcript lands in the app you were using. By default the audio stays on the
Mac.

The name already promised this, but the old build did not keep it. Apple Speech
was configured to allow Apple's servers, and an "Agent rewrite" feature sent
transcripts to the Claude, Codex or Coco CLIs. The README had to say "this is not
an on-device-only workflow". After the redesign it is on-device unless the user
turns that off.

## What changed

**Removed: Agent rewrite (about 3,300 lines including tests).**
- `AIRewriteService.swift` (1,142 lines), which spawned and supervised CLI
  processes, kept warm Claude/Codex sessions and handled timeouts.
- `HushwordCore/AIPolish.swift`: prompts, output sanitizing, provider enums and
  command builders.
- The long-press `Fn` gesture and the `Option+Shift+Space` shortcut.
  `FunctionKeyClickState` and `FunctionKeyMonitor` now recognize taps only, so a
  slow tap can no longer be read as a rewrite request and swallowed.
- The machinery for replacing the last insertion: `TextInserter.replace`,
  synthetic backspaces for iTerm, and the selection and interaction snapshots in
  `CorrectionObservation`. `CorrectionObservation` now does one thing: it watches
  the pasted range for a stable user edit that feeds Correction Memory.
- The Agent picker, availability status, rewrite buttons and HUD rewriting state.

Why remove it: the feature cut against the product's purpose, needed
third-party CLIs on the user's PATH, and accounted for the largest and most
fragile code in the repo (process supervision, JSON-RPC, deadlines).
Dictation never depended on it.

**Added: one privacy switch, "Keep audio on this Mac" (default on).**
- `AppSettings.keepAudioOnMac` is `true` by default. Older settings files that
  lack the key also load as `true`.
- `SpeechRecognitionPolicy.dictation(keepAudioOnMac:)` returns `.onDeviceOnly`
  or `.serverAllowed`. The policy goes through
  `DictationEngine.start` → `SpeechCapturing.start` →
  `SpeechRecognitionService`. When it is on-device only, the legacy
  `SFSpeechRecognizer` path sets `requiresOnDeviceRecognition` and skips
  recognizers that lack on-device support. On macOS 26 the on-device
  `DictationTranscriber` covers the gap, and otherwise Whisper transcribes alone.
- Onboarding version bumped to 2, so existing users see the new privacy default
  once.

**Kept unchanged:** whole-recording capture, parallel Apple and Whisper
recognition with deterministic candidate selection, transcript cleanup, personal
dictionary, Correction Memory, terminology hints, paste-target locking, HUD, the
supervised `whisper.cpp` server, verified model download, Sparkle updates and
the release scripts. These were well factored and tested.

## Architecture now

```text
Fn tap / Option-Space ─► AppModel ─► DictationEngine ─► SpeechRecognitionService
                           │               │                 ├─ WAV capture
                           │               │                 ├─ Apple (policy: on-device | server)
                           │               │                 └─ Whisper (local HTTP server)
                           │               └─ candidate selection + TranscriptCleaner
                           ├─ PasteTargetTracker ─► TextInserter ─► CorrectionObservation
                           └─ AppStore (settings, history, learned corrections)
```

`CONTEXT.md` has the domain terms and invariants. It now includes "no dictated
text goes to an AI service" and "Apple returns empty rather than use a server
when keepAudioOnMac is set".

## How to run

```bash
swift run HushwordCoreTests      # 69 pass
swift run HushwordAppKitTests    # 45 pass
swift build -c release --product Hushword
./scripts/install.sh             # builds whisper.cpp + app, installs to /Applications
```

## Known risk

With the default on, a language that has no on-device Apple model on that Mac
(older macOS, before macOS 26) gets no Apple transcript. Until the Whisper model
finishes downloading, that dictation produces nothing. Settings and the support
page explain this, but it has not been measured on real hardware.

## What I'd build next

1. **Measure the on-device default.** Use a small synthetic zh/en/mixed corpus to
   compare word error rate for Apple on-device, Apple server and Whisper alone,
   and use the numbers to decide whether the default is costly.
2. **Show "Whisper not ready and no on-device Apple model" in the HUD** instead
   of silently inserting nothing.
3. **Split `AppModel` (about 670 lines):** move permission handling and
   end-to-end timing into their own types so AppModel only handles session state.
4. **Move the two hand-rolled test runners to `swift-testing`** once the
   toolchain floor allows it, so `swift test` works.
