import Darwin
import AVFoundation
import Carbon
import FlowTypeCore
import FlowTypeAppKit
import Foundation
import SwiftUI

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
final class SpeechCaptureStub: SpeechCapturing {
    let stopDelayNanoseconds: UInt64
    let result: SpeechRecognitionResult

    init(
        stopDelayNanoseconds: UInt64 = 0,
        result: SpeechRecognitionResult
    ) {
        self.stopDelayNanoseconds = stopDelayNanoseconds
        self.result = result
    }

    func start(
        localeIdentifier: String,
        contextualStrings: [String],
        onAudioLevel: @escaping (Double) -> Void
    ) async throws {}

    func stop() async -> SpeechRecognitionResult {
        try? await Task.sleep(nanoseconds: stopDelayNanoseconds)
        return result
    }

    func shutdown() {}
}

@main
struct DictationEngineTestRunner {
    @MainActor
    static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
            (
                "preserves the safer Whisper candidate",
                finalizationPreservesTheSaferWhisperCandidate
            ),
            (
                "uses the Apple whole recording as a punctuation fallback",
                finalizationUsesAppleWholeRecordingAsPunctuationFallback
            ),
            (
                "prefers the Apple candidate for short Chinese",
                finalizationPrefersAppleCandidateForShortChinese
            ),
            (
                "selects immutable recognition evidence before cleanup",
                finalizationSelectsRecognitionEvidenceBeforeCleanup
            ),
            (
                "owns a local HTTP server lifecycle",
                ownsLocalHTTPServerLifecycle
            ),
            (
                "restarts a local HTTP server immediately after shutdown",
                restartsLocalHTTPServerImmediatelyAfterShutdown
            ),
            (
                "passes runtime environment to a local HTTP server",
                passesRuntimeEnvironmentToLocalHTTPServer
            ),
            (
                "keeps Whisper warm for two idle minutes",
                keepsWhisperWarmForTwoIdleMinutes
            ),
            (
                "releases Whisper safely under memory pressure",
                releasesWhisperSafelyUnderMemoryPressure
            ),
            (
                "removes only stale FlowType temporary files",
                removesOnlyStaleFlowTypeTemporaryFiles
            ),
            (
                "builds structured local recognition timing",
                buildsStructuredLocalRecognitionTiming
            ),
            (
                "records Whisper audio as 16 kHz mono Int16",
                recordsWhisperAudioAs16kHzMonoInt16
            ),
            (
                "recognizes a recording even when the HUD level misses speech",
                recognizesRecordingWhenHUDLevelMissesSpeech
            ),
            (
                "respects the user's default microphone",
                respectsUsersDefaultMicrophone
            ),
            (
                "builds and cleans a file-backed multipart upload",
                buildsAndCleansFileBackedMultipartUpload
            ),
            (
                "decodes word confidence from verbose Whisper JSON",
                decodesWordConfidenceFromVerboseWhisperJSON
            ),
            (
                "converts microphone audio to the Whisper recording format",
                convertsMicrophoneAudioToWhisperRecordingFormat
            ),
            (
                "preserves duration across consecutive audio buffers",
                preservesDurationAcrossConsecutiveAudioBuffers
            ),
            (
                "keeps only one hundred private end-to-end timings",
                keepsOnlyOneHundredPrivateEndToEndTimings
            ),
            (
                "keeps a new listening HUD visible after an old hide completes",
                keepsNewListeningHUDAfterOldHideCompletes
            ),
            (
                "uses a stationary all-spaces HUD window",
                usesStationaryAllSpacesHUDWindow
            ),
            (
                "closes AI rewrite process standard input",
                closesAIRewriteProcessStandardInput
            ),
            (
                "cancels an AI rewrite process promptly",
                cancelsAIRewriteProcessPromptly
            ),
            (
                "propagates AI rewrite cancellation to its process",
                propagatesAIRewriteCancellationToItsProcess
            ),
            (
                "routes local dictation and Agent rewrite shortcuts independently",
                routesLocalDictationAndAgentRewriteShortcutsIndependently
            ),
            (
                "selects the configured Agent for long-press rewrite",
                selectsConfiguredAgentForLongPressRewrite
            ),
            (
                "defaults old settings to automatic Agent selection",
                defaultsOldSettingsToAutomaticAgentSelection
            ),
            (
                "presents onboarding once for legacy settings",
                presentsOnboardingOnceForLegacySettings
            ),
            (
                "explains when no bring-your-own Agent is available",
                explainsWhenNoBringYourOwnAgentIsAvailable
            ),
            (
                "accepts only complete automatic update configuration",
                acceptsOnlyCompleteAutomaticUpdateConfiguration
            ),
            (
                "accepts only secure product support links",
                acceptsOnlySecureProductSupportLinks
            ),
            (
                "caps long-press rewrite latency",
                capsLongPressRewriteLatency
            ),
            (
                "shows a copied rewrite as successful delivery",
                showsCopiedRewriteAsSuccessfulDelivery
            ),
            (
                "uses a prewarmed no-thinking Haiku session",
                usesPrewarmedNoThinkingHaikuSession
            ),
            (
                "reuses a prewarmed Codex app-server session",
                reusesPrewarmedCodexAppServerSession
            ),
            (
                "meets the live Codex long-press deadline",
                meetsLiveCodexLongPressDeadline
            ),
            (
                "requires a ready session for fast rewrite",
                requiresReadySessionForFastRewrite
            ),
            (
                "waits for in-flight fast session preparation",
                waitsForInFlightFastSessionPreparation
            ),
            (
                "includes fast session preparation in the rewrite deadline",
                includesFastSessionPreparationInRewriteDeadline
            ),
            (
                "recovers a fast session after timeout",
                recoversFastSessionAfterTimeout
            ),
            (
                "applies a per-request AI rewrite timeout",
                appliesPerRequestAIRewriteTimeout
            ),
            (
                "replaces only an unchanged last insertion",
                replacesOnlyUnchangedLastInsertion
            ),
            (
                "selects the pasted range only while its caret stays unchanged",
                selectsPastedRangeOnlyWhileItsCaretStaysUnchanged
            ),
            (
                "finds the exact iTerm pasted range through NUL separators",
                findsExactITermPastedRangeThroughNULSeparators
            ),
            (
                "prefers the exact selection over a terminal text snapshot",
                prefersExactSelectionOverTerminalTextSnapshot
            ),
            (
                "uses verified backward deletion for terminal input",
                usesVerifiedBackwardDeletionForTerminalInput
            ),
            (
                "captures the exact UTF-16 inserted text range",
                capturesExactUTF16InsertedTextRange
            ),
            (
                "recovers the inserted range after paste",
                recoversInsertedRangeAfterPaste
            ),
            (
                "persists learned corrections locally",
                persistsLearnedCorrectionsLocally
            ),
            (
                "pins the official large v3 turbo Q5 asset",
                pinsOfficialLargeV3TurboQ5Asset
            ),
            (
                "uses the release model mirror from bundle metadata",
                usesReleaseModelMirrorFromBundleMetadata
            ),
            (
                "uses Apple recognition while the Whisper model is unavailable",
                usesAppleRecognitionWhileWhisperModelIsUnavailable
            ),
            (
                "uses modern Apple dictation only when it is supported",
                usesModernAppleDictationOnlyWhenSupported
            ),
            (
                "selects only a strongly supported Apple alternative",
                selectsOnlyStronglySupportedAppleAlternative
            ),
            (
                "keeps Apple's first candidate when semantic evidence is weak",
                keepsFirstAppleCandidateWhenSemanticEvidenceIsWeak
            ),
            (
                "keeps Apple's first candidate when the changed segment is confident",
                keepsFirstAppleCandidateWhenChangedSegmentIsConfident
            ),
            (
                "rejects a structurally drifting Apple alternative",
                rejectsStructurallyDriftingAppleAlternative
            ),
            (
                "prefers the bundled Whisper runtime",
                prefersBundledWhisperRuntime
            ),
            (
                "atomically installs a verified Whisper model",
                atomicallyInstallsVerifiedWhisperModel
            ),
            (
                "preserves an installed model when verification fails",
                preservesInstalledModelWhenVerificationFails
            ),
            (
                "marks a verified Whisper model as runtime ready",
                marksVerifiedWhisperModelAsRuntimeReady
            ),
            (
                "downloads and prepares the Whisper model in the background",
                downloadsAndPreparesWhisperModelInBackground
            ),
            (
                "reports model download progress and retries failures",
                reportsModelDownloadProgressAndRetriesFailures
            ),
            (
                "shows and reuses one settings window",
                showsAndReusesOneSettingsWindow
            ),
            (
                "shows settings after the popover closes",
                showsSettingsAfterPopoverCloses
            ),
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        if failures > 0 {
            exit(1)
        }
    }

    private static func routesLocalDictationAndAgentRewriteShortcutsIndependently() async throws {
        let local = GlobalHotKeyShortcut.localDictation
        let rewrite = GlobalHotKeyShortcut.agentRewrite

        guard local.keyCode == UInt32(kVK_Space),
              local.modifiers == UInt32(optionKey),
              local.action == .localDictation,
              rewrite.keyCode == UInt32(kVK_Space),
              rewrite.modifiers == UInt32(optionKey | shiftKey),
              rewrite.action == .agentRewrite,
              local.identifier != rewrite.identifier else {
            throw TestFailure(
                description: "local dictation and Agent rewrite shortcuts are not isolated"
            )
        }
    }

    private static func selectsConfiguredAgentForLongPressRewrite() async throws {
        guard AgentProviderSelection.resolve(
            preference: .auto,
            availableProviders: [.claude, .codex, .coco],
            readyProviders: [.codex]
        ) == .codex,
        AgentProviderSelection.resolve(
            preference: .claude,
            availableProviders: [.claude, .codex],
            readyProviders: [.codex]
        ) == .claude,
        AgentProviderSelection.resolve(
            preference: .codex,
            availableProviders: [.claude, .codex],
            readyProviders: [.claude]
        ) == .codex,
        AgentProviderSelection.resolve(
            preference: .coco,
            availableProviders: [.coco],
            readyProviders: []
        ) == .coco,
        AgentProviderSelection.resolve(
            preference: .off,
            availableProviders: [.claude, .codex, .coco],
            readyProviders: [.claude, .codex]
        ) == nil else {
            throw TestFailure(
                description: "Fn long press ignored the configured Agent"
            )
        }
    }

    private static func defaultsOldSettingsToAutomaticAgentSelection() async throws {
        let data = Data(
            """
            {
              "autoPaste": true,
              "language": "zh-CN",
              "dictionaryText": "长心存储 = 长鑫存储"
            }
            """.utf8
        )
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        guard settings.agentPreference == .auto,
              settings.autoPaste,
              settings.language == "zh-CN",
              settings.dictionaryText == "长心存储 = 长鑫存储" else {
            throw TestFailure(
                description: "old settings did not retain values with Auto Agent"
            )
        }
    }

    private static func presentsOnboardingOnceForLegacySettings() async throws {
        let data = Data(
            """
            {
              "autoPaste": true,
              "language": "zh-CN"
            }
            """.utf8
        )
        let legacySettings = try JSONDecoder().decode(
            AppSettings.self,
            from: data
        )
        let completedSettings = AppSettings(
            onboardingVersion: OnboardingPolicy.currentVersion
        )

        guard legacySettings.onboardingVersion == 0,
              OnboardingPolicy.shouldPresent(
                completedVersion: legacySettings.onboardingVersion
              ),
              !OnboardingPolicy.shouldPresent(
                completedVersion: completedSettings.onboardingVersion
              ) else {
            throw TestFailure(
                description: "first-run onboarding is not presented exactly once"
            )
        }
    }

    private static func explainsWhenNoBringYourOwnAgentIsAvailable() async throws {
        let missing = AgentAvailabilityPolicy.status(
            preference: .auto,
            availableProviders: []
        )
        let codex = AgentAvailabilityPolicy.status(
            preference: .codex,
            availableProviders: [.codex]
        )

        guard missing.selectedProvider == nil,
              missing.detail.contains("Dictation still works"),
              missing.detail.contains("install"),
              codex.selectedProvider == .codex,
              codex.detail.contains("Codex"),
              codex.detail.contains("provider") else {
            throw TestFailure(
                description: "Agent dependency status is ambiguous"
            )
        }
    }

    private static func acceptsOnlyCompleteAutomaticUpdateConfiguration() async throws {
        let complete = UpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://updates.example.com/appcast.xml",
                "SUPublicEDKey": "public-key",
            ]
        )
        let missingKey = UpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://updates.example.com/appcast.xml",
            ]
        )
        let insecure = UpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "http://updates.example.com/appcast.xml",
                "SUPublicEDKey": "public-key",
            ]
        )

        guard complete?.feedURL.absoluteString
                == "https://updates.example.com/appcast.xml",
              missingKey == nil,
              insecure == nil else {
            throw TestFailure(
                description: "automatic updates accepted incomplete release metadata"
            )
        }
    }

    private static func acceptsOnlySecureProductSupportLinks() async throws {
        let links = ProductLinks(
            infoDictionary: [
                "FlowTypeSupportURL": "https://example.com/support",
                "FlowTypePrivacyURL": "https://example.com/privacy",
            ]
        )
        let insecure = ProductLinks(
            infoDictionary: [
                "FlowTypeSupportURL": "http://example.com/support",
                "FlowTypePrivacyURL": "https://example.com/privacy",
            ]
        )

        guard links?.supportURL.absoluteString
                == "https://example.com/support",
              links?.privacyURL.absoluteString
                == "https://example.com/privacy",
              insecure == nil else {
            throw TestFailure(
                description: "product links accepted incomplete or insecure metadata"
            )
        }
    }

    private static func capsLongPressRewriteLatency() async throws {
        guard AgentRewritePolicy.longPressActivationNanoseconds
                + AgentRewritePolicy.longPressTimeoutNanoseconds
                <= 3_000_000_000,
              AgentRewritePolicy.longPressTimeoutNanoseconds
                <= 2_500_000_000 else {
            throw TestFailure(
                description: "Fn long press can keep the user waiting over three seconds"
            )
        }
    }

    private static func showsCopiedRewriteAsSuccessfulDelivery() async throws {
        let status = AppStatus.copied(
            "Copied. The last dictation was not replaced."
        )
        let presentation = DictationPresentation(
            lifecycleState: status.lifecycleState,
            audioLevel: 0
        )

        guard presentation.hudPhase == .success,
              status.title == "Copied. The last dictation was not replaced." else {
            throw TestFailure(
                description: "a successful clipboard fallback still shows Try again"
            )
        }
    }

    private static func usesPrewarmedNoThinkingHaikuSession() async throws {
        let command = AICommandBuilder.buildClaudeSession(
            homeDirectory: "/Users/test"
        )
        guard command.executable == "/Users/test/.local/bin/claude",
              command.arguments.contains("--model"),
              command.arguments.contains("haiku"),
              command.arguments.contains("--input-format"),
              command.arguments.contains("stream-json"),
              command.arguments.contains("--include-partial-messages"),
              command.environment["MAX_THINKING_TOKENS"] == "0" else {
            throw TestFailure(
                description: "fast rewrite does not use a reusable no-thinking Haiku session"
            )
        }
    }

    private static func reusesPrewarmedCodexAppServerSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-codex-warm-session-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let codexDirectory = directory.appendingPathComponent(
            ".codex",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )
        let authURL = codexDirectory.appendingPathComponent("auth.json")
        try "{}".write(to: authURL, atomically: true, encoding: .utf8)
        let executableURL = binDirectory.appendingPathComponent("codex")
        let logURL = directory.appendingPathComponent("requests.log")
        let codexHomeURL = directory.appendingPathComponent("codex-home.txt")
        try """
        #!/bin/sh
        printf '%s' "$CODEX_HOME" > '\(codexHomeURL.path)'
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          printf '%s\n' "$line" >> '\(logURL.path)'
          if [ "$count" -eq 1 ]; then
            printf '%s\n' '{"id":1,"result":{"userAgent":"fake"}}'
          elif [ "$count" -eq 3 ]; then
            printf '%s\n' '{"id":2,"result":{"thread":{"id":"thread-1"}}}'
          elif [ "$count" -eq 4 ]; then
            printf '%s\n' '{"id":3,"result":{"turn":{"id":"turn-1"}}}'
            printf '%s\n' '{"method":"item/completed","params":{"item":{"type":"agentMessage","id":"message-1","text":"READY","phase":"final_answer"},"threadId":"thread-1","turnId":"turn-1","completedAtMs":1}}'
          elif [ "$count" -eq 5 ]; then
            printf '%s\n' '{"id":4,"result":{"turn":{"id":"turn-2"}}}'
            printf '%s\n' '{"method":"item/completed","params":{"item":{"type":"agentMessage","id":"message-2","text":"Codex 已润色。","phase":"final_answer"},"threadId":"thread-1","turnId":"turn-2","completedAtMs":2}}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        guard await service.prepareFastRewrite(provider: .codex) else {
            let requests = (try? String(
                contentsOf: logURL,
                encoding: .utf8
            )) ?? "no requests"
            throw TestFailure(
                description: "Codex app-server did not warm up: \(requests)"
            )
        }
        let rewritten = try await service.rewriteFast(
            "请润色。",
            with: .codex,
            mode: .natural,
            timeoutNanoseconds: 500_000_000
        )
        let requests = try String(contentsOf: logURL, encoding: .utf8)
        let isolatedHomePath = try String(
            contentsOf: codexHomeURL,
            encoding: .utf8
        )
        let isolatedHome = URL(fileURLWithPath: isolatedHomePath)
        let isolatedConfig = try String(
            contentsOf: isolatedHome.appendingPathComponent("config.toml"),
            encoding: .utf8
        )
        let isolatedAuth = isolatedHome.appendingPathComponent("auth.json")
        guard isolatedHomePath.contains("flowtype-codex-"),
              isolatedHomePath != codexDirectory.path,
              FileManager.default.fileExists(atPath: isolatedAuth.path),
              isolatedConfig.contains("model = \"gpt-5.5\""),
              isolatedConfig.contains("service_tier = \"priority\""),
              requests.contains("\"model\":\"gpt-5.5\""),
              requests.contains("\"serviceTier\":\"priority\"") else {
            throw TestFailure(
                description: "Codex fast session still loads the global Agent environment"
            )
        }
        await service.shutdownFastRewrite()
        guard rewritten == "Codex 已润色。",
              !FileManager.default.fileExists(
                atPath: isolatedHome.path
              ) else {
            throw TestFailure(
                description: "Codex did not reuse and clean its isolated app-server: \(rewritten)"
            )
        }
    }

    private static func meetsLiveCodexLongPressDeadline() async throws {
        guard ProcessInfo.processInfo.environment[
            "FLOWTYPE_LIVE_CODEX_TEST"
        ] == "1" else {
            return
        }

        let service = AIRewriteService()
        guard await service.prepareFastRewrite(provider: .codex) else {
            throw TestFailure(
                description: "live Codex app-server did not warm up"
            )
        }
        do {
            let rewritten = try await service.rewriteFast(
                "嗯我觉得这个其实可以先做然后我们明天再看一下效果",
                with: .codex,
                mode: .natural,
                timeoutNanoseconds:
                    AgentRewritePolicy.longPressTimeoutNanoseconds
            )
            await service.shutdownFastRewrite()
            guard rewritten.contains("先做"),
                  rewritten.contains("明天") else {
                throw TestFailure(
                    description: "live Codex changed the original meaning: \(rewritten)"
                )
            }
        } catch {
            await service.shutdownFastRewrite()
            throw error
        }
    }

    private static func requiresReadySessionForFastRewrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-warm-session-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            printf '%s\n' '{"type":"result","result":"预热后的结果。"}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        do {
            _ = try await service.rewriteFast(
                "请润色。",
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "fast rewrite started a cold session on demand"
            )
        } catch AIRewriteService.RewriteError.fastSessionNotReady {
        }

        guard await service.prepareFastRewrite() else {
            throw TestFailure(description: "fast rewrite session did not warm up")
        }
        let rewritten = try await service.rewriteFast(
            "请润色。",
            mode: .natural,
            timeoutNanoseconds: 100_000_000
        )
        await service.shutdownFastRewrite()
        guard rewritten == "预热后的结果。" else {
            throw TestFailure(
                description: "fast rewrite did not reuse its warm process: \(rewritten)"
            )
        }
    }

    private static func waitsForInFlightFastSessionPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-preparation-race-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let markerURL = directory.appendingPathComponent("warming")
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            touch '\(markerURL.path)'
            sleep 0.15
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            printf '%s\n' '{"type":"result","result":"预热竞态已处理。"}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        let preparation = Task {
            await service.prepareFastRewrite()
        }
        await Task.yield()
        for _ in 0..<400 where !FileManager.default.fileExists(
            atPath: markerURL.path
        ) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            throw TestFailure(description: "fast rewrite preparation never started")
        }

        let rewritten = try await service.rewriteFast(
            "请润色。",
            mode: .natural,
            timeoutNanoseconds: 500_000_000
        )
        let prepared = await preparation.value
        await service.shutdownFastRewrite()
        guard prepared, rewritten == "预热竞态已处理。" else {
            throw TestFailure(
                description: "fast rewrite rejected an in-flight warm session"
            )
        }
    }

    private static func includesFastSessionPreparationInRewriteDeadline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-preparation-deadline-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let markerURL = directory.appendingPathComponent("warming")
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            touch '\(markerURL.path)'
            sleep 1
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            printf '%s\n' '{"type":"result","result":"不应等到这个结果。"}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        let preparation = Task {
            await service.prepareFastRewrite()
        }
        await Task.yield()
        for _ in 0..<400 where !FileManager.default.fileExists(
            atPath: markerURL.path
        ) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            throw TestFailure(description: "fast rewrite preparation never started")
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await service.rewriteFast(
                "请润色。",
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "fast rewrite ignored its preparation deadline"
            )
        } catch AIRewriteService.RewriteError.timedOut {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 1 else {
                throw TestFailure(
                    description: "fast rewrite waited beyond its total deadline"
                )
            }
        }
        preparation.cancel()
        await service.shutdownFastRewrite()
    }

    private static func recoversFastSessionAfterTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-fast-timeout-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            sleep 30
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        guard await service.prepareFastRewrite() else {
            throw TestFailure(description: "fast rewrite session did not warm up")
        }
        do {
            _ = try await service.rewriteFast(
                "请润色。",
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "slow fast rewrite unexpectedly completed"
            )
        } catch AIRewriteService.RewriteError.timedOut {
        }
        guard await service.prepareFastRewrite() else {
            throw TestFailure(
                description: "fast rewrite session did not recover after timeout"
            )
        }
        await service.shutdownFastRewrite()
    }

    private static func appliesPerRequestAIRewriteTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-request-timeout-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        sleep 30
        printf 'late result'
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(
            homeDirectory: directory.path,
            timeoutNanoseconds: 30_000_000_000
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await service.rewrite(
                "Please rewrite this.",
                with: .claude,
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "slow AI rewrite unexpectedly completed"
            )
        } catch AIRewriteService.RewriteError.timedOut {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 2 else {
                throw TestFailure(
                    description: "per-request AI rewrite timeout was ignored"
                )
            }
        }
    }

    private static func replacesOnlyUnchangedLastInsertion() async throws {
        let snapshot = CorrectionObservationSnapshot(
            originalText: "开头本地听写结尾",
            insertedRange: NSRange(location: 2, length: 4)
        )

        guard snapshot.canReplaceInsertedText(in: "开头本地听写结尾"),
              snapshot.canReplaceInsertedText(in: "开头本地听写结尾，新增"),
              snapshot.canReplaceInsertedText(in: "开头已经修改结尾") == false else {
            throw TestFailure(
                description: "Agent rewrite can overwrite text changed after dictation"
            )
        }
    }

    private static func selectsPastedRangeOnlyWhileItsCaretStaysUnchanged() async throws {
        let interaction = ReplacementInteractionSnapshot(
            keyDownCount: 10,
            leftMouseDownCount: 20,
            rightMouseDownCount: 30,
            otherMouseDownCount: 40,
            scrollWheelCount: 50
        )
        let snapshot = SelectionReplacementSnapshot.make(
            beforePasteRange: NSRange(location: 4, length: 0),
            afterPasteRange: NSRange(location: 20, length: 0),
            insertedText: "Hi 👋，世界",
            interaction: interaction
        )

        guard snapshot?.insertedRange == NSRange(location: 4, length: 16),
              snapshot?.matchesSelectedText("H\u{0}i\u{0} 👋，世界\u{0}") == true,
              snapshot?.matchesSelectedText("Hi 👋，世") == false,
              snapshot?.canReplace(
                currentSelectedRange: NSRange(location: 20, length: 0),
                interaction: interaction
              ) == true,
              snapshot?.canReplace(
                currentSelectedRange: NSRange(location: 19, length: 0),
                interaction: interaction
              ) == false,
              snapshot?.canReplace(
                currentSelectedRange: NSRange(location: 20, length: 0),
                interaction: ReplacementInteractionSnapshot(
                    keyDownCount: 11,
                    leftMouseDownCount: 20,
                    rightMouseDownCount: 30,
                    otherMouseDownCount: 40,
                    scrollWheelCount: 50
                )
              ) == false else {
            throw TestFailure(
                description: "range replacement can select stale or edited input"
            )
        }
    }

    private static func findsExactITermPastedRangeThroughNULSeparators() async throws {
        let insertedText = "FlowType覆盖测试原文"
        let prefix = "/model"
        let rawInsertedText = insertedText.map { "\($0)\u{0}" }.joined()
        let rawText = (prefix + rawInsertedText) as NSString
        let caretRange = NSRange(location: rawText.length, length: 0)
        let expectedRange = NSRange(
            location: (prefix as NSString).length,
            length: (rawInsertedText as NSString).length
        )

        let foundRange = SelectionReplacementPolicy.findInsertedRange(
            endingAt: caretRange,
            insertedText: insertedText,
            selectedText: { range in
                guard NSMaxRange(range) <= rawText.length else { return nil }
                return rawText.substring(with: range)
            }
        )

        guard foundRange == expectedRange else {
            throw TestFailure(
                description: "iTerm pasted range was guessed from the prompt instead of matched text"
            )
        }
    }

    private static func prefersExactSelectionOverTerminalTextSnapshot() async throws {
        let interaction = ReplacementInteractionSnapshot(
            keyDownCount: 10,
            leftMouseDownCount: 20,
            rightMouseDownCount: 30,
            otherMouseDownCount: 40,
            scrollWheelCount: 50
        )
        let exactSelection = SelectionReplacementSnapshot(
            caretRange: NSRange(location: 20, length: 0),
            insertedRange: NSRange(location: 6, length: 14),
            insertedText: "FlowType覆盖测试原文",
            interaction: interaction
        )
        let terminalTextSnapshot = CorrectionObservationSnapshot(
            originalText: "/modelFlowType覆盖测试原文",
            insertedRange: NSRange(location: 0, length: 20)
        )

        let range = SelectionReplacementPolicy.preferredInsertedRange(
            selectionSnapshot: exactSelection,
            textSnapshot: terminalTextSnapshot,
            currentText: "/modelFlowType覆盖测试原文",
            currentSelectedRange: NSRange(location: 20, length: 0),
            interaction: interaction
        )

        guard range == exactSelection.insertedRange else {
            throw TestFailure(
                description: "terminal replacement preferred an unverified prompt range"
            )
        }
    }

    private static func usesVerifiedBackwardDeletionForTerminalInput() async throws {
        guard SelectionReplacementPolicy.replacementAction(
            applicationBundleIdentifier: "com.googlecode.iterm2",
            currentText: "提示符\0FlowType\0覆盖\0测试\0原文\0",
            insertedText: "FlowType覆盖测试原文",
            insertedRange: NSRange(location: 4, length: 18)
        ) == .deleteBackward(characterCount: 14),
        SelectionReplacementPolicy.replacementAction(
            applicationBundleIdentifier: "com.apple.TextEdit",
            currentText: "前缀FlowType覆盖测试原文",
            insertedText: "FlowType覆盖测试原文",
            insertedRange: NSRange(location: 2, length: 14)
        ) == .pasteOverSelection else {
            throw TestFailure(
                description: "terminal replacement still relies on an ignored AX selection"
            )
        }
    }

    @MainActor
    private static func finalizationPreservesTheSaferWhisperCandidate() async throws {
        let whisper = "我们用 random signal，在 fine-tuning 的情况下也能达到结果，所以能发 paper 吗？"
        let engine = DictationEngine(
            speechCapture: SpeechCaptureStub(
                result: SpeechRecognitionResult(
                    whisperTranscript: whisper,
                    appleTranscript: nil
                )
            )
        )

        let result = await engine.finish(
            context: DictationContext(personalDictionaryText: "")
        )

        guard result == whisper else {
            throw TestFailure(
                description: "expected \(whisper.debugDescription), got \(result.debugDescription)"
            )
        }
    }

    @MainActor
    private static func finalizationUsesAppleWholeRecordingAsPunctuationFallback() async throws {
        let whisper = "我们已经做了很多实验RL不是交给模型新的能力使用 random signal在 fine-tuning 的情况下也可以达到类似结果所以我们能发 paper 吗?现在只是说这个定义是怎么回事"
        let appleTranscript = "我们已经做了很多实验，RL 不是交给模型新的能力。使用 random sick know，在 fine to ling 的情况下也可以达到类似结果。所以我们能发 PK 吗？现在只是说，这个定义是怎么回事？"
        let engine = DictationEngine(
            speechCapture: SpeechCaptureStub(
                result: SpeechRecognitionResult(
                    whisperTranscript: whisper,
                    appleTranscript: appleTranscript
                )
            )
        )

        let result = await engine.finish(
            context: DictationContext(personalDictionaryText: "")
        )

        let expected = "我们已经做了很多实验，RL不是交给模型新的能力。使用 random signal，在 fine-tuning 的情况下也可以达到类似结果。所以我们能发 paper 吗？现在只是说，这个定义是怎么回事？"
        guard result == expected else {
            throw TestFailure(
                description: "Apple live punctuation was discarded; "
                    + "expected \(expected.debugDescription), "
                    + "got \(result.debugDescription)"
            )
        }
    }

    @MainActor
    private static func finalizationPrefersAppleCandidateForShortChinese() async throws {
        let appleFinal = "昨晚的识别度最好。"
        let engine = DictationEngine(
            speechCapture: SpeechCaptureStub(
                result: SpeechRecognitionResult(
                    whisperTranscript: "昨晚的识别都。",
                    appleTranscript: appleFinal
                )
            )
        )

        let result = await engine.finish(
            context: DictationContext(personalDictionaryText: "")
        )

        guard result == appleFinal else {
            throw TestFailure(
                description: "expected Apple final \(appleFinal.debugDescription), "
                    + "got \(result.debugDescription)"
            )
        }
    }

    @MainActor
    private static func finalizationSelectsRecognitionEvidenceBeforeCleanup() async throws {
        let engine = DictationEngine(
            speechCapture: SpeechCaptureStub(
                result: SpeechRecognitionResult(
                    whisperTranscript:
                        "we work with random signal no actually plain method today",
                    appleTranscript:
                        "we work with criteria and a plain method today."
                )
            )
        )

        let result = await engine.finish(
            context: DictationContext(personalDictionaryText: "")
        )

        guard result == "we work with plain method today." else {
            throw TestFailure(
                description:
                    "surface cleanup changed which recognition evidence won: \(result)"
            )
        }
    }

    @MainActor
    private static func ownsLocalHTTPServerLifecycle() async throws {
        let port = 19_000 + Int(getpid() % 1_000)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        let server = LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "flowtype-test-http-server",
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [
                    "-m", "http.server", String(port),
                    "--bind", "127.0.0.1",
                ],
                healthURL: healthURL,
                maximumStartupChecks: 40,
                startupCheckIntervalNanoseconds: 50_000_000
            )
        )

        guard await server.startIfNeeded(),
              await server.isHealthy() else {
            throw TestFailure(description: "managed local HTTP server did not become healthy")
        }

        server.shutdown()
        for _ in 0..<20 where await server.isHealthy() {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard await server.isHealthy() == false else {
            throw TestFailure(description: "managed local HTTP server survived shutdown")
        }
    }

    @MainActor
    private static func restartsLocalHTTPServerImmediatelyAfterShutdown() async throws {
        let port = 20_000 + Int(getpid() % 1_000)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        let server = LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "flowtype-test-restart-server",
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [
                    "-m", "http.server", String(port),
                    "--bind", "127.0.0.1",
                ],
                healthURL: healthURL,
                maximumStartupChecks: 80,
                startupCheckIntervalNanoseconds: 25_000_000
            )
        )

        guard await server.startIfNeeded() else {
            throw TestFailure(description: "restart test server did not start")
        }
        server.shutdown()
        guard await server.startIfNeeded() else {
            throw TestFailure(description: "server did not restart immediately after shutdown")
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard await server.isHealthy() else {
            throw TestFailure(description: "restarted server disappeared after old cleanup")
        }
        server.shutdown()
    }

    @MainActor
    private static func passesRuntimeEnvironmentToLocalHTTPServer() async throws {
        let port = 21_000 + Int(getpid() % 1_000)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        let environmentValue = "flowtype-backends-\(UUID().uuidString)"
        let script = """
        import http.server
        import os

        value = os.environ.get("FLOWTYPE_RUNTIME_TEST", "")

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = value.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                pass

        http.server.HTTPServer(("127.0.0.1", \(port)), Handler).serve_forever()
        """
        let server = LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "flowtype-test-environment-server",
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-c", script],
                environment: ["FLOWTYPE_RUNTIME_TEST": environmentValue],
                healthURL: healthURL,
                maximumStartupChecks: 40,
                startupCheckIntervalNanoseconds: 50_000_000
            )
        )

        guard await server.startIfNeeded() else {
            throw TestFailure(description: "environment test server did not start")
        }
        defer { server.shutdown() }

        let (body, _) = try await URLSession.shared.data(from: healthURL)
        guard String(data: body, encoding: .utf8) == environmentValue else {
            throw TestFailure(description: "local server lost its runtime environment")
        }
    }

    @MainActor
    private static func keepsWhisperWarmForTwoIdleMinutes() async throws {
        guard WhisperLifecyclePolicy.idleShutdownNanoseconds
            == 120_000_000_000 else {
            throw TestFailure(description: "Whisper idle shutdown is not two minutes")
        }
    }

    @MainActor
    private static func releasesWhisperSafelyUnderMemoryPressure() async throws {
        var state = WhisperMemoryPressureState()
        guard state.receivePressure() else {
            throw TestFailure(
                description: "idle Whisper did not release under memory pressure"
            )
        }

        state.beginTranscription()
        guard state.receivePressure() == false,
              state.finishTranscription(),
              state.finishTranscription() == false else {
            throw TestFailure(
                description: "active Whisper was interrupted or deferred release repeated"
            )
        }
    }

    @MainActor
    private static func removesOnlyStaleFlowTypeTemporaryFiles() async throws {
        let fileManager = FileManager.default
        let cleanupDirectories = Set(
            FlowTypeTemporaryFileCleanup.defaultDirectories(
                fileManager: fileManager
            ).map(\.standardizedFileURL.path)
        )
        guard cleanupDirectories.contains(
            fileManager.temporaryDirectory.standardizedFileURL.path
        ),
        cleanupDirectories.contains(
            URL(fileURLWithPath: "/tmp").standardizedFileURL.path
        ) else {
            throw TestFailure(
                description: "startup cleanup missed a FlowType temporary root"
            )
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "flowtype-cleanup-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let staleDate = Date(timeIntervalSince1970: 1_000)
        let now = staleDate.addingTimeInterval(
            FlowTypeTemporaryFileCleanup.staleAge + 1
        )
        let token = UUID().uuidString
        let staleNames = [
            "flowtype-\(token).wav",
            "flowtype-upload-\(token).multipart",
            "flowtype-whisper-\(token).download",
            "flowtype-ai-\(token).stdout",
        ]
        let staleDirectoryName = "flowtype-codex-\(token)"
        let retainedNames = [
            "flowtype-\(token).wav.backup",
            "flowtype-not-a-uuid.wav",
            "unrelated-\(token).wav",
        ]

        for name in staleNames + retainedNames {
            let url = directory.appendingPathComponent(name)
            fileManager.createFile(atPath: url.path, contents: Data([1]))
            try fileManager.setAttributes(
                [.modificationDate: staleDate],
                ofItemAtPath: url.path
            )
        }
        let staleDirectory = directory.appendingPathComponent(
            staleDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: staleDirectory,
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: staleDirectory.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.modificationDate: staleDate],
            ofItemAtPath: staleDirectory.path
        )
        let recentURL = directory.appendingPathComponent(
            "flowtype-\(UUID().uuidString).wav"
        )
        fileManager.createFile(atPath: recentURL.path, contents: Data([1]))
        try fileManager.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: recentURL.path
        )

        let removed = FlowTypeTemporaryFileCleanup.removeStaleFiles(
            in: directory,
            now: now,
            fileManager: fileManager
        )
        let removedNames = Set(removed.map { $0.lastPathComponent })
        let staleFilesAreGone = (staleNames + [staleDirectoryName])
            .allSatisfy { name in
            !fileManager.fileExists(
                atPath: directory.appendingPathComponent(name).path
            )
        }
        let retainedFilesRemain = (
            retainedNames + [recentURL.lastPathComponent]
        ).allSatisfy { name in
            fileManager.fileExists(
                atPath: directory.appendingPathComponent(name).path
            )
        }
        guard removedNames == Set(staleNames + [staleDirectoryName]),
              staleFilesAreGone,
              retainedFilesRemain else {
            throw TestFailure(
                description: "temporary cleanup removed the wrong files: \(removed)"
            )
        }
    }

    @MainActor
    private static func buildsStructuredLocalRecognitionTiming() async throws {
        let snapshot = RecognitionTimingSnapshot(
            appleMilliseconds: 612,
            whisperMilliseconds: 571,
            totalMilliseconds: 615,
            appleWasEmpty: false,
            whisperWasEmpty: false,
            selectedSource: .whisper
        )
        guard snapshot.selectedSource == .whisper,
              snapshot.logMessage.contains("apple_ms=612"),
              snapshot.logMessage.contains("whisper_ms=571"),
              snapshot.logMessage.contains("total_ms=615"),
              snapshot.logMessage.contains("selected=whisper"),
              snapshot.logMessage.contains("apple_empty=false"),
              snapshot.logMessage.contains("whisper_empty=false") else {
            throw TestFailure(
                description: "recognition timing is not structured: \(snapshot.logMessage)"
            )
        }
    }

    @MainActor
    private static func recordsWhisperAudioAs16kHzMonoInt16() async throws {
        guard WhisperAudioPolicy.sampleRate == 16_000,
              WhisperAudioPolicy.channelCount == 1,
              WhisperAudioPolicy.commonFormat == .pcmFormatInt16,
              WhisperAudioPolicy.isInterleaved,
              let format = WhisperAudioPolicy.makeFormat(),
              format.sampleRate == 16_000,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16,
              format.isInterleaved else {
            throw TestFailure(description: "Whisper recording format regressed")
        }
    }

    @MainActor
    private static func recognizesRecordingWhenHUDLevelMissesSpeech() async throws {
        guard RecordingFinalizationPolicy.shouldRecognize(
            hasRecordingFile: true,
            detectedSpeech: false
        ) else {
            throw TestFailure(
                description: "HUD audio level incorrectly discarded a complete recording"
            )
        }
    }

    @MainActor
    private static func respectsUsersDefaultMicrophone() async throws {
        let devices = [
            AudioInputDeviceCandidate(
                identifier: 41,
                hasInput: true,
                isBuiltIn: false
            ),
            AudioInputDeviceCandidate(
                identifier: 79,
                hasInput: true,
                isBuiltIn: true
            ),
        ]
        guard AudioInputDevicePolicy.preferredDeviceIdentifier(
            devices: devices,
            defaultDeviceIdentifier: 41
        ) == 41 else {
            throw TestFailure(
                description: "FlowType overrode the user's working default microphone"
            )
        }
    }

    @MainActor
    private static func buildsAndCleansFileBackedMultipartUpload() async throws {
        let fileManager = FileManager.default
        let audioURL = fileManager.temporaryDirectory
            .appendingPathComponent("flowtype-multipart-test-\(UUID().uuidString).wav")
        let audio = Data([0, 1, 2, 3, 4, 5, 6, 7])
        try audio.write(to: audioURL)
        defer { try? fileManager.removeItem(at: audioURL) }

        let upload = try MultipartUploadFile(
            fields: [
                "language": "zh",
                "beam_size": "1",
                "best_of": "1",
            ],
            audioURL: audioURL
        )
        let bodyURL = upload.bodyURL
        guard fileManager.fileExists(atPath: bodyURL.path),
              bodyURL != audioURL,
              let bodySize = try? fileManager
                .attributesOfItem(atPath: bodyURL.path)[.size] as? NSNumber,
              bodySize.intValue > audio.count else {
            throw TestFailure(description: "multipart upload was not file-backed")
        }

        let body = try Data(contentsOf: bodyURL)
        guard let text = String(data: body, encoding: .isoLatin1),
              text.contains("name=\"language\"\r\n\r\nzh"),
              text.contains("name=\"beam_size\"\r\n\r\n1"),
              text.contains("name=\"best_of\"\r\n\r\n1"),
              text.contains("filename=\"recording.wav\"") else {
            throw TestFailure(description: "multipart upload lost request fields")
        }

        upload.cleanup()
        guard fileManager.fileExists(atPath: bodyURL.path) == false else {
            throw TestFailure(description: "multipart upload file survived cleanup")
        }
    }

    @MainActor
    private static func decodesWordConfidenceFromVerboseWhisperJSON() async throws {
        let data = Data(
            """
            {
              "text": "所以我们能发 paper 吗？",
              "segments": [
                {
                  "words": [
                    {"word": "所以", "probability": 0.99},
                    {"word": " paper", "probability": 0.72}
                  ]
                },
                {
                  "words": [
                    {"word": "吗", "probability": 0.98}
                  ]
                }
              ]
            }
            """.utf8
        )
        let candidate = try WhisperServerResponseDecoder.decode(data)
        guard candidate.text == "所以我们能发 paper 吗？",
              candidate.words == [
                  WhisperWordConfidence(text: "所以", probability: 0.99),
                  WhisperWordConfidence(text: " paper", probability: 0.72),
                  WhisperWordConfidence(text: "吗", probability: 0.98),
              ] else {
            throw TestFailure(
                description: "verbose Whisper confidence was lost: \(candidate)"
            )
        }
    }

    @MainActor
    private static func convertsMicrophoneAudioToWhisperRecordingFormat() async throws {
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ),
        let outputFormat = WhisperAudioPolicy.makeFormat(),
        let input = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: 4_800
        ) else {
            throw TestFailure(description: "could not create audio conversion fixtures")
        }
        input.frameLength = 4_800
        if let samples = input.floatChannelData?[0] {
            for index in 0..<Int(input.frameLength) {
                samples[index] = sin(Float(index) * 0.05) * 0.25
            }
        }

        let output = try AudioBufferConverter().convert(
            input,
            to: outputFormat
        )
        guard output.format.sampleRate == 16_000,
              output.format.channelCount == 1,
              output.format.commonFormat == .pcmFormatInt16,
              output.format.isInterleaved,
              (1_590...1_610).contains(Int(output.frameLength)) else {
            throw TestFailure(
                description: "unexpected Whisper buffer: "
                    + "\(output.format), frames=\(output.frameLength)"
            )
        }
    }

    @MainActor
    private static func preservesDurationAcrossConsecutiveAudioBuffers() async throws {
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ),
        let outputFormat = WhisperAudioPolicy.makeFormat() else {
            throw TestFailure(description: "could not create continuous conversion formats")
        }

        let converter = AudioBufferConverter()
        var outputFrames = 0
        for bufferIndex in 0..<47 {
            guard let input = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: 1_024
            ) else {
                throw TestFailure(description: "could not create continuous input buffer")
            }
            input.frameLength = 1_024
            if let samples = input.floatChannelData?[0] {
                for frameIndex in 0..<Int(input.frameLength) {
                    let sampleIndex = bufferIndex * 1_024 + frameIndex
                    samples[frameIndex] = sin(Float(sampleIndex) * 0.03) * 0.25
                }
            }
            outputFrames += Int(
                try converter.convert(input, to: outputFormat).frameLength
            )
        }

        let expectedFrames = Int(
            (Double(47 * 1_024) / 3.0).rounded()
        )
        guard abs(outputFrames - expectedFrames) <= 2 else {
            throw TestFailure(
                description: "continuous conversion lost duration: "
                    + "expected \(expectedFrames), got \(outputFrames)"
            )
        }
    }

    @MainActor
    private static func keepsOnlyOneHundredPrivateEndToEndTimings() async throws {
        let records = (0..<125).map { index in
            EndToEndTimingRecord(
                startToListeningMilliseconds: Int64(index),
                stopToRecognitionReadyMilliseconds: 600,
                targetActivationMilliseconds: 50,
                pasteMilliseconds: 2,
                stopToTextDeliveredMilliseconds: 652,
                autoPaste: true,
                outcome: .pasted
            )
        }
        let trimmed = EndToEndTimingStore.trimmedRecords(records)
        guard EndToEndTimingStore.maximumRecords == 100,
              trimmed.count == 100,
              trimmed.first?.startToListeningMilliseconds == 25,
              trimmed.last?.startToListeningMilliseconds == 124 else {
            throw TestFailure(description: "end-to-end timing ring buffer is unbounded")
        }

        let encoded = try JSONEncoder().encode(trimmed.last)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let keys = Set((object as? [String: Any])?.keys.map { $0 } ?? [])
        guard keys.contains("stopToTextDeliveredMilliseconds"),
              keys.contains("outcome"),
              keys.contains("transcript") == false,
              keys.contains("text") == false,
              keys.contains("applicationName") == false else {
            throw TestFailure(
                description: "end-to-end timing persisted sensitive keys: \(keys)"
            )
        }
    }

    @MainActor
    private static func keepsNewListeningHUDAfterOldHideCompletes() async throws {
        var visibility = DictationHUDVisibilityState()
        let oldHideGeneration = visibility.beginHide()
        visibility.beginShow()

        guard visibility.shouldCompleteHide(
            generation: oldHideGeneration
        ) == false else {
            throw TestFailure(
                description: "an old HUD fade-out hid a new listening session"
            )
        }
    }

    @MainActor
    private static func usesStationaryAllSpacesHUDWindow() async throws {
        let behavior = DictationHUDWindowPolicy.collectionBehavior
        guard behavior.contains(.canJoinAllSpaces),
              behavior.contains(.fullScreenAuxiliary),
              behavior.contains(.stationary),
              behavior.contains(.transient) == false else {
            throw TestFailure(
                description: "HUD can still be hidden by Space or Exposé management"
            )
        }
    }

    @MainActor
    private static func closesAIRewriteProcessStandardInput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-stdin-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")

        let status = try await AIProcessRunner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "if read line; then exit 9; else printf eof; fi",
            ],
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            timeoutNanoseconds: 2_000_000_000
        )

        guard status == 0,
              try String(contentsOf: stdoutURL, encoding: .utf8) == "eof" else {
            throw TestFailure(
                description: "AI rewrite process inherited an open standard input"
            )
        }
    }

    @MainActor
    private static func cancelsAIRewriteProcessPromptly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-cancel-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await AIProcessRunner.run(
                executable: "/bin/sleep",
                arguments: ["30"],
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                timeoutNanoseconds: 30_000_000_000
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(
                description: "cancelled AI rewrite unexpectedly completed"
            )
        } catch is CancellationError {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 2 else {
                throw TestFailure(
                    description: "cancelled AI rewrite kept running"
                )
            }
        }
    }

    @MainActor
    private static func propagatesAIRewriteCancellationToItsProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-ai-service-cancel-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        sleep 30
        printf 'late result'
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(
            homeDirectory: directory.path,
            timeoutNanoseconds: 30_000_000_000
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await service.rewrite(
                "Please rewrite this.",
                with: .claude,
                mode: .natural
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(
                description: "cancelled AI rewrite unexpectedly completed"
            )
        } catch is CancellationError {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 2 else {
                throw TestFailure(
                    description: "AI rewrite cancellation did not reach its process"
                )
            }
        }
    }

    @MainActor
    private static func capturesExactUTF16InsertedTextRange() async throws {
        let snapshot = CorrectionObservationSnapshot.make(
            originalText: "标题：",
            insertionLocation: 3,
            insertedText: "这么转的话。"
        )
        guard snapshot == CorrectionObservationSnapshot(
            originalText: "标题：这么转的话。",
            insertedRange: NSRange(location: 3, length: 6)
        ) else {
            throw TestFailure(
                description: "correction observation lost the exact inserted range"
            )
        }
    }

    private static func recoversInsertedRangeAfterPaste() async throws {
        let snapshot = CorrectionObservationSnapshot.makeAfterPaste(
            currentText: "标题：这么转的话。结尾",
            caretLocation: 9,
            insertedText: "这么转的话。"
        )
        guard snapshot == CorrectionObservationSnapshot(
            originalText: "标题：这么转的话。结尾",
            insertedRange: NSRange(location: 3, length: 6)
        ),
        CorrectionObservationSnapshot.makeAfterPaste(
            currentText: "标题：已经不同。结尾",
            caretLocation: 9,
            insertedText: "这么转的话。"
        ) == nil else {
            throw TestFailure(
                description: "post-paste capture trusted the wrong text range"
            )
        }
    }

    @MainActor
    private static func persistsLearnedCorrectionsLocally() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtype-correction-store-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppStore(directory: directory)
        let corrections = [
            LearnedCorrection(
                observed: "这么转的话",
                preferred: "这么赚的话"
            ),
            LearnedCorrection(
                observed: "Type less",
                preferred: "Typeless"
            ),
        ]
        store.saveLearnedCorrections(corrections)

        guard AppStore(directory: directory).loadLearnedCorrections()
            == corrections else {
            throw TestFailure(
                description: "learned corrections did not survive a local reload"
            )
        }
    }

    @MainActor
    private static func pinsOfficialLargeV3TurboQ5Asset() async throws {
        let asset = WhisperModelAsset.largeV3TurboQ5
        guard asset.fileName == "ggml-large-v3-turbo-q5_0.bin",
              asset.downloadURL.absoluteString
                == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
              asset.expectedByteCount == 574_041_195,
              asset.sha256
                == "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2" else {
            throw TestFailure(description: "official Q5 asset metadata drifted: \(asset)")
        }
    }

    private static func usesReleaseModelMirrorFromBundleMetadata() async throws {
        let asset = WhisperModelAsset.distributionLargeV3TurboQ5(
            infoDictionary: [
                "FlowTypeWhisperModelURL":
                    "https://downloads.example.com/models/flowtype-q5.bin",
            ]
        )
        guard asset.downloadURL.absoluteString
                == "https://downloads.example.com/models/flowtype-q5.bin",
              asset.expectedByteCount
                == WhisperModelAsset.largeV3TurboQ5.expectedByteCount,
              asset.sha256 == WhisperModelAsset.largeV3TurboQ5.sha256 else {
            throw TestFailure(
                description: "release metadata did not preserve the pinned model identity"
            )
        }
    }

    @MainActor
    private static func usesAppleRecognitionWhileWhisperModelIsUnavailable() async throws {
        let unavailableStates: [WhisperModelState] = [
            .notInstalled,
            .downloading,
            .verifying,
            .failed("network unavailable"),
        ]
        guard unavailableStates.allSatisfy({
            WhisperModelAvailabilityPolicy.shouldAttemptWhisper(for: $0) == false
        }) else {
            throw TestFailure(description: "Whisper was attempted before its model was ready")
        }

        let appleTranscript = "Apple Speech remains available."
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: nil,
            appleTranscript: appleTranscript,
            contextualStrings: []
        )
        guard selected == appleTranscript else {
            throw TestFailure(description: "Apple fallback was lost without the Q5 model")
        }
    }

    @MainActor
    private static func usesModernAppleDictationOnlyWhenSupported() async throws {
        guard AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: true,
            localeIsSupported: true
        ) == .modernDictation,
        AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: false,
            localeIsSupported: true
        ) == .legacy,
        AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: true,
            localeIsSupported: false
        ) == .legacy else {
            throw TestFailure(
                description: "modern Apple dictation fallback policy is unsafe"
            )
        }
    }

    @MainActor
    private static func selectsOnlyStronglySupportedAppleAlternative() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "这么赚的话，他早上可以不接单呀",
            "这么拽的话，他早上可以不接单呀",
        ]
        let scores = [
            candidates[0]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.72,
                changedTermRelevance: 0.70
            ),
            candidates[1]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.91,
                changedTermRelevance: 0.90
            ),
            candidates[2]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.63,
                changedTermRelevance: 0.95
            ),
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.423
                ),
            ],
            semanticScore: { candidate, _, _ in scores[candidate] }
        )

        guard selected == candidates[1],
              candidates.contains(selected) else {
            throw TestFailure(
                description: "selector generated or chose an unsupported transcript: \(selected)"
            )
        }
    }

    @MainActor
    private static func keepsFirstAppleCandidateWhenSemanticEvidenceIsWeak() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "这么赚的话，他早上可以不接单呀",
            "这么拽的话，他早上可以不接单呀",
        ]
        let scores = [
            candidates[0]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.720,
                changedTermRelevance: 0.720
            ),
            candidates[1]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.725,
                changedTermRelevance: 0.725
            ),
            candidates[2]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.719,
                changedTermRelevance: 0.719
            ),
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.423
                ),
            ],
            semanticScore: { candidate, _, _ in scores[candidate] }
        )

        guard selected == candidates[0] else {
            throw TestFailure(
                description: "weak evidence replaced Apple's first transcript: \(selected)"
            )
        }
    }

    @MainActor
    private static func keepsFirstAppleCandidateWhenChangedSegmentIsConfident() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "这么赚的话，他早上可以不接单呀",
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.92
                ),
            ],
            semanticScore: { candidate, _, _ in
                AppleCandidateSemanticScore(
                    sentenceRelevance: candidate == candidates[1] ? 1.0 : 0.0,
                    changedTermRelevance: candidate == candidates[1] ? 1.0 : 0.0
                )
            }
        )

        guard selected == candidates[0] else {
            throw TestFailure(
                description: "a confident Apple segment was unnecessarily replaced"
            )
        }
    }

    @MainActor
    private static func rejectsStructurallyDriftingAppleAlternative() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "他决定明天早上完全不再接任何订单",
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.423
                ),
            ],
            semanticScore: { candidate, _, _ in
                AppleCandidateSemanticScore(
                    sentenceRelevance: candidate == candidates[1] ? 1.0 : 0.0,
                    changedTermRelevance: candidate == candidates[1] ? 1.0 : 0.0
                )
            }
        )

        guard selected == candidates[0] else {
            throw TestFailure(
                description: "a structurally different transcript replaced Apple's first choice"
            )
        }
    }

    @MainActor
    private static func prefersBundledWhisperRuntime() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-runtime-test-\(UUID().uuidString)")
        let appURL = root.appendingPathComponent("FlowType.app", isDirectory: true)
        let runtimeDirectory = appURL
            .appendingPathComponent("Contents/Resources/WhisperRuntime")
        let bundledServer = runtimeDirectory
            .appendingPathComponent("whisper-server-apple_m4")
        try FileManager.default.createDirectory(
            at: bundledServer.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: bundledServer)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundledServer.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        guard let runtime = WhisperRuntimeLocator.locate(
            appBundleURL: appURL,
            cpuBrand: "Apple M4 Pro",
            homebrewPrefixes: [root.appendingPathComponent("fake-homebrew")]
        ),
        runtime.serverExecutableURL == bundledServer,
        runtime.environment.isEmpty else {
            throw TestFailure(description: "bundled Whisper runtime was not preferred")
        }
    }

    @MainActor
    private static func atomicallyInstallsVerifiedWhisperModel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-model-install-\(UUID().uuidString)")
        let downloadURL = root.appendingPathComponent("download.partial")
        let modelsDirectory = root.appendingPathComponent("Models")
        let bytes = Data("verified model bytes".utf8)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try bytes.write(to: downloadURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let asset = WhisperModelAsset(
            fileName: "fixture.bin",
            downloadURL: URL(string: "https://example.com/fixture.bin")!,
            expectedByteCount: Int64(bytes.count),
            sha256: "03cfa25d83f5eaa1faac98ed6ceaaf0e7afe3c273a1e1502c2714ebe10b8263e"
        )
        let installedURL = try WhisperModelInstaller.installDownloadedFile(
            at: downloadURL,
            asset: asset,
            modelsDirectory: modelsDirectory
        )

        guard installedURL == modelsDirectory.appendingPathComponent("fixture.bin"),
              try Data(contentsOf: installedURL) == bytes,
              FileManager.default.fileExists(atPath: downloadURL.path) == false else {
            throw TestFailure(description: "verified model was not atomically installed")
        }
    }

    @MainActor
    private static func preservesInstalledModelWhenVerificationFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-model-reject-\(UUID().uuidString)")
        let modelsDirectory = root.appendingPathComponent("Models")
        let installedURL = modelsDirectory.appendingPathComponent("fixture.bin")
        let downloadURL = root.appendingPathComponent("download.partial")
        let originalBytes = Data("known good model".utf8)
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        try originalBytes.write(to: installedURL)
        try Data("corrupt replacement".utf8).write(to: downloadURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let asset = WhisperModelAsset(
            fileName: "fixture.bin",
            downloadURL: URL(string: "https://example.com/fixture.bin")!,
            expectedByteCount: 19,
            sha256: String(repeating: "0", count: 64)
        )
        do {
            _ = try WhisperModelInstaller.installDownloadedFile(
                at: downloadURL,
                asset: asset,
                modelsDirectory: modelsDirectory
            )
            throw TestFailure(description: "corrupt model unexpectedly installed")
        } catch let failure as TestFailure {
            throw failure
        } catch {
            guard try Data(contentsOf: installedURL) == originalBytes else {
                throw TestFailure(
                    description: "failed verification replaced the working model"
                )
            }
        }
    }

    @MainActor
    private static func marksVerifiedWhisperModelAsRuntimeReady() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-model-marker-\(UUID().uuidString)")
        let downloadURL = root.appendingPathComponent("download.partial")
        let modelsDirectory = root.appendingPathComponent("Models")
        let bytes = Data("verified model bytes".utf8)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try bytes.write(to: downloadURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let asset = WhisperModelAsset(
            fileName: "fixture.bin",
            downloadURL: URL(string: "https://example.com/fixture.bin")!,
            expectedByteCount: Int64(bytes.count),
            sha256: "03cfa25d83f5eaa1faac98ed6ceaaf0e7afe3c273a1e1502c2714ebe10b8263e"
        )
        let installedURL = try WhisperModelInstaller.installDownloadedFile(
            at: downloadURL,
            asset: asset,
            modelsDirectory: modelsDirectory
        )

        guard WhisperModelInstaller.verifiedModelURL(
            asset: asset,
            modelsDirectory: modelsDirectory
        ) == installedURL else {
            throw TestFailure(description: "verified model was not runtime ready")
        }
    }

    @MainActor
    private static func downloadsAndPreparesWhisperModelInBackground() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-model-manager-\(UUID().uuidString)")
        let modelsDirectory = root.appendingPathComponent("Models")
        let bytes = Data("verified model bytes".utf8)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let asset = WhisperModelAsset(
            fileName: "fixture.bin",
            downloadURL: URL(string: "https://example.com/fixture.bin")!,
            expectedByteCount: Int64(bytes.count),
            sha256: "03cfa25d83f5eaa1faac98ed6ceaaf0e7afe3c273a1e1502c2714ebe10b8263e"
        )
        let manager = WhisperModelManager(
            asset: asset,
            modelsDirectory: modelsDirectory,
            downloader: { _, _ in
                let downloadURL = root.appendingPathComponent(
                    "download-\(UUID().uuidString).partial"
                )
                try bytes.write(to: downloadURL)
                return downloadURL
            }
        )
        guard manager.state == .notInstalled else {
            throw TestFailure(description: "new manager did not begin as not installed")
        }

        await manager.prepare()

        guard manager.state == .ready,
              WhisperModelInstaller.verifiedModelURL(
                  asset: asset,
                  modelsDirectory: modelsDirectory
              ) != nil else {
            throw TestFailure(
                description: "background model preparation ended in \(manager.state)"
            )
        }
    }

    @MainActor
    private static func reportsModelDownloadProgressAndRetriesFailures() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-model-progress-\(UUID().uuidString)")
        let modelsDirectory = root.appendingPathComponent("Models")
        let bytes = Data("verified model bytes".utf8)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let asset = WhisperModelAsset(
            fileName: "fixture.bin",
            downloadURL: URL(string: "https://example.com/fixture.bin")!,
            expectedByteCount: Int64(bytes.count),
            sha256: "03cfa25d83f5eaa1faac98ed6ceaaf0e7afe3c273a1e1502c2714ebe10b8263e"
        )
        var attempts = 0
        let manager = WhisperModelManager(
            asset: asset,
            modelsDirectory: modelsDirectory,
            downloader: { _, reportProgress in
                attempts += 1
                reportProgress(0.42)
                try await Task.sleep(nanoseconds: 80_000_000)
                if attempts == 1 {
                    throw URLError(.networkConnectionLost)
                }
                let downloadURL = root.appendingPathComponent(
                    "download-\(UUID().uuidString).partial"
                )
                try bytes.write(to: downloadURL)
                return downloadURL
            }
        )

        let firstAttempt = Task { await manager.prepare() }
        for _ in 0..<100 where manager.downloadProgress != 0.42 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        guard manager.downloadProgress == 0.42,
              manager.statusText.contains("42%") else {
            throw TestFailure(
                description: "model download progress was not visible"
            )
        }
        await firstAttempt.value
        guard case .failed = manager.state,
              manager.downloadProgress == nil else {
            throw TestFailure(
                description: "failed model download did not become retryable"
            )
        }

        await manager.prepare()
        guard attempts == 2,
              manager.state == .ready,
              manager.downloadProgress == nil else {
            throw TestFailure(
                description: "model download did not recover after retry"
            )
        }
    }

    @MainActor
    private static func showsAndReusesOneSettingsWindow() async throws {
        let controller = SettingsWindowController(
            rootView: Text("Settings regression test")
        )

        controller.show(activateApplication: false)
        guard let firstWindow = controller.window,
              firstWindow.isVisible else {
            throw TestFailure(description: "settings window did not become visible")
        }

        controller.show(activateApplication: false)
        guard controller.window === firstWindow else {
            throw TestFailure(description: "opening settings created duplicate windows")
        }
        firstWindow.close()
    }

    @MainActor
    private static func showsSettingsAfterPopoverCloses() async throws {
        let controller = SettingsWindowController(
            rootView: Text("Deferred settings regression test")
        )
        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let anchor = NSButton(title: "Open", target: nil, action: nil)
        hostWindow.contentView = anchor
        hostWindow.makeKeyAndOrderFront(nil)
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: Text("Popover").frame(width: 160, height: 100)
        )
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .minY
        )

        guard popover.isShown else {
            throw TestFailure(description: "test popover did not open")
        }
        controller.showAfterClosingPopover(
            popover,
            activateApplication: false
        )
        guard controller.window?.isVisible == false else {
            throw TestFailure(description: "settings appeared before the popover closed")
        }

        for _ in 0..<100 where controller.window?.isVisible == false {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        guard popover.isShown == false,
              controller.window?.isVisible == true else {
            throw TestFailure(
                description: "settings did not appear after the popover closed "
                    + "(popover shown: \(popover.isShown), "
                    + "window visible: \(controller.window?.isVisible == true))"
            )
        }
        controller.window?.close()
        hostWindow.close()
    }
}
