# Hushword

Speak, then get back to what you were writing. Hushword is a native macOS menu
bar dictation app that inserts your transcript into the app you were using.
Audio stays on your Mac by default: local Whisper and Apple's on-device speech
models transcribe the same recording, and nothing is sent to an AI service.

**Apple Silicon · macOS 13.3+ · Build from source**

[Install](#build-and-install-from-source) · [How it works](#use-hushword) ·
[Processing and privacy](#processing-and-privacy) · [Development](#development)

## Use Hushword

1. Place the cursor where you want to write, then tap `Fn` to start recording.
2. Speak, then tap `Fn` again. Hushword processes the whole recording and inserts
   the selected transcript. If automatic paste is unavailable, use the clipboard.

| Action | Shortcut |
|---|---|
| Start or stop dictation | Tap `Fn`, or `Option + Space` |

Settings has one privacy switch, **Keep audio on this Mac** (on by default).
See [processing and privacy](#processing-and-privacy).

## What it does

- **Stay in your app.** A compact HUD shows recording, processing and completion
  without taking focus; the transcript returns to the original paste target.
- **Recognize the whole utterance.** Apple Speech and local Whisper Q5 process
  the same completed WAV in parallel. Lightweight rules choose between their
  transcripts without starting a text-generation model.
- **Keep technical terms useful.** Chinese, English, Japanese and Korean presets,
  mixed Chinese-English terminology, a personal dictionary and narrow local
  Correction Memory support repeated writing workflows.
- **Keep dictation available during model setup.** The size- and SHA-256-verified
  Q5 download runs in the background while Apple Speech remains available.
  The bundled Apple Silicon Whisper runtime needs no Homebrew on the target Mac.
- **Never rewrite your meaning.** Cleanup removes fillers, repetitions and
  spoken formatting commands. No language model rewrites the transcript.

Recordings, history, settings and Correction Memory stay under
`~/Library/Application Support/Hushword`. The only network traffic is the
one-time Whisper model download, update checks in release builds, and Apple
Speech server recognition if you turn **Keep audio on this Mac** off.

## Build and install from source

Hushword currently targets Apple Silicon Macs running macOS 13.3 or newer.

```bash
git clone https://github.com/mynotwo/hushword.git
cd hushword
./scripts/install.sh
```

The script builds the app and its pinned `whisper.cpp` runtime, ad-hoc signs the
bundle, copies it to `/Applications/Hushword.app`, and opens it. Building from
source requires Swift 6.0 or newer, CMake, and the macOS Command Line Tools. Running the
installed app does not require Homebrew or CMake.

The installer replaces any existing `/Applications/Hushword.app` and closes a
running Hushword before opening the new build. This is a source-build route,
not a notarized public installer.

On first use, macOS asks for:

1. Microphone access
2. Speech Recognition access
3. Accessibility access for automatic paste

If Accessibility is denied, Hushword still copies the result to the clipboard.

For a small private beta, `./scripts/package_beta.sh` creates an ad-hoc signed
DMG. Testers must use macOS's explicit Open action on first launch. This beta
artifact is not suitable for public sale.

## Development

```bash
# Core behavior tests
swift run HushwordCoreTests

# App orchestration and local-process integration tests
swift run HushwordAppKitTests

# Debug build
swift build

# Build the app bundle
./scripts/build_app.sh
```

See [CONTEXT.md](CONTEXT.md) for the domain language, module map, and refactoring
invariants. A focused bug report should include macOS version, Apple chip,
shortcut, language, the Keep-audio setting and the observed behavior. Use a synthetic
utterance rather than private recordings or dictation history.

## Distribution

Development builds use the stable local bundle ID and an ad-hoc signature.
Customer releases require a permanent bundle ID, Developer ID Application
certificate, Apple notarization profile, HTTPS model mirror, Sparkle key and
update feed, support URL, privacy URL, and support email.

Copy `scripts/release.env.example` to a private shell configuration, replace
every placeholder with real release infrastructure, source it, then run:

```bash
./scripts/release.sh
```

The script refuses the development bundle ID and incomplete or non-HTTPS
metadata. It signs embedded Whisper and Sparkle components inside-out, verifies
the app, notarizes and staples it, creates and notarizes a DMG, generates a
signed Sparkle appcast, and renders the static download/privacy/support site.
Credentials and signing keys are read from the Keychain or environment and are
never written into the repository.

Sparkle update signing keys can be initialized once with:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account hushword
```

Before public distribution, install the final DMG on a clean Apple Silicon Mac
with no developer tools and verify:

- first launch, icon, Gatekeeper, microphone, Speech Recognition, Accessibility
- refusal of each permission and later re-authorization
- no network, interrupted model download, checksum failure, and Retry
- dictation in each language preset with Keep audio on this Mac on and off
- automatic update from the previous notarized public version

## Text commands

- `comma`, `period`, `question mark`, `new line`
- `逗号`, `句号`, `问号`, `冒号`, `换行`, `新的一行`
- Self-correction example: `Let's meet Tuesday, no actually Wednesday`

## Personal dictionary

Users can open Settings and enter one replacement per line. Manual entries
always override Correction Memory and history-derived terminology hints:

```text
长心存储 = 长鑫存储
see ex em tee = CXMT
```

Correction Memory is maintained separately in local Application Support and
learns only narrow, direct edits observed immediately after automatic paste.
Repeated technical terms in local history are recognition hints only; they do
not become replacements.

## Scope

This MVP covers system-wide dictation; account sync, usage billing and mobile
clients are outside its current scope. The workflow was inspired by Typeless.
Hushword is an independent implementation and uses no Typeless code, branding
or services.

## Processing and privacy

Hushword records one complete local WAV, then gives that same recording to
Apple Speech and a prewarmed local Whisper Q5 recognizer in parallel. Whisper
runs on this Mac. Hushword picks between the two complete transcripts with
lightweight deterministic rules; it never generates words of its own.

With **Keep audio on this Mac** on (the default), Apple Speech runs only with
on-device models: `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, or the
on-device `DictationTranscriber` on macOS 26. If a language has no on-device Apple
model, Whisper transcribes alone. Turning the switch off lets Apple Speech use
Apple's servers, which can help accuracy for some languages.

On first launch, the 574 MB Q5 model downloads and is verified by size and
SHA-256 in the background; Apple Speech remains available during that setup.
Hushword has no accounts, analytics or AI rewrite service.
