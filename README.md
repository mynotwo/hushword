# FlowType

FlowType is a native macOS menu bar dictation app inspired by the workflow of Typeless. It is an independent implementation and does not use Typeless code, branding, or services.

## Current MVP

- Tap `Fn` to start dictation and tap it again to stop and insert
- Hold `Fn` for half a second after insertion for a fast configurable Agent rewrite
- `Option + Space` remains available as an alternate shortcut
- `Option + Shift + Space` remains available as an alternate rewrite shortcut
- Compact bottom HUD with a microphone-driven waveform, processing spinner, and completion state without taking focus
- Records the complete utterance before Apple Speech and local Whisper Q5 recognize the same WAV in parallel
- Chinese, English, Japanese, and Korean presets with mixed Chinese-English terminology
- Whole-recording recognition protects sentence endings instead of selecting streaming fragments
- Recognizer-owned sentence boundaries plus conservative Apple-to-Whisper punctuation transfer
- Lightweight local selection between Apple and Whisper without starting a text-generation model
- Prefers Apple for short Chinese disagreements and Whisper for mixed-language terminology
- Self-contained Apple Silicon Whisper runtime; customer Macs do not need Homebrew
- Verified Q5 model download runs in the background while Apple Speech stays available
- First-run setup explains shortcuts and requests each permission explicitly
- Download percentage, clear failure state, and one-click local-model retry
- Personal dictionary with `spoken form = preferred spelling`
- Local Correction Memory learns only narrow edits made directly after paste; manual entries always win
- Repeated technical terms from local history are recognition hints, never automatic replacements
- Copies or pastes the final transcript into the app that was active before dictation
- Local-only history and settings under `~/Library/Application Support/FlowType`
- Whisper prewarms when recording starts, sleeps after two idle minutes, and falls back to Apple when unavailable
- Optional `Auto / Claude / Codex / Coco / Off` Agent selection for the post-dictation shortcut
- Signed automatic updates through Sparkle when release metadata is configured

## Install

FlowType currently targets Apple Silicon Macs running macOS 13.3 or newer.

```bash
./scripts/install.sh
```

The script builds the app and its pinned `whisper.cpp` runtime, ad-hoc signs the
bundle, copies it to `/Applications/FlowType.app`, and opens it. Building from
source requires Swift, CMake, and the macOS Command Line Tools. Running the
installed app does not require Homebrew or CMake.

On first use, macOS asks for:

1. Microphone access
2. Speech Recognition access
3. Accessibility access for automatic paste

If Accessibility is denied, FlowType still copies the result to the clipboard.

For a small private beta, `./scripts/package_beta.sh` creates an ad-hoc signed
DMG. Testers must use macOS's explicit Open action on first launch. This beta
artifact is not suitable for public sale.

## Development

```bash
# Core behavior tests
swift run FlowTypeCoreTests

# App orchestration and local-process integration tests
swift run FlowTypeAppKitTests

# Debug build
swift build

# Build the app bundle
./scripts/build_app.sh
```

See `CONTEXT.md` for the domain language, module map, and refactoring invariants.

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
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account flowtype
```

Before public distribution, install the final DMG on a clean Apple Silicon Mac
with no developer tools and verify:

- first launch, icon, Gatekeeper, microphone, Speech Recognition, Accessibility
- refusal of each permission and later re-authorization
- no network, interrupted model download, checksum failure, and Retry
- normal dictation with no Claude, Codex, or Coco installed
- each configured Agent while signed in and while signed out
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

This MVP covers the core system-wide dictation workflow. It does not include account sync, usage billing, mobile clients, or Typeless-specific proprietary behavior.

## Processing and privacy

FlowType records one complete local WAV, then provides that same recording to
Apple Speech and a prewarmed local Whisper Q5 recognizer in parallel. Whisper
runs on this Mac. Apple Speech may use Apple's service because FlowType does not
force on-device-only recognition. FlowType selects between their complete
transcripts with lightweight deterministic rules. On first launch, the 574 MB
Q5 model downloads and is verified by size and SHA-256 in the background; Apple
Speech remains available during that setup. Normal dictation has no Qwen
adapter; Q8 and Qwen are not required or loaded.

Normal dictation does not wait for an Agent. Manual rewrite sends the displayed
text to the selected external provider. After local dictation has been inserted,
holding `Fn` for half a second sends that transcript to the Agent selected in
Settings and replaces only the unchanged insertion FlowType recorded. `Auto`
uses a prewarmed Claude Haiku session when Claude is installed, otherwise a
dedicated ephemeral Codex app-server session. If the target or text can no
longer be verified safely, FlowType copies the rewrite and leaves the existing
text alone. FlowType stops a long-press rewrite that cannot finish within three
seconds, leaving the original text unchanged. Coco remains available as a
slower manual full-Agent rewrite.
