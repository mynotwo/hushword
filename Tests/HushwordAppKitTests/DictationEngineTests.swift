import Darwin
import HushwordCore
import HushwordAppKit
import Foundation

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
                "removes only stale Hushword temporary files",
                removesOnlyStaleHushwordTemporaryFiles
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
    private static func removesOnlyStaleHushwordTemporaryFiles() async throws {
        let fileManager = FileManager.default
        let cleanupDirectories = Set(
            HushwordTemporaryFileCleanup.defaultDirectories(
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
                description: "startup cleanup missed a Hushword temporary root"
            )
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "hushword-cleanup-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: directory) }

        let staleDate = Date(timeIntervalSince1970: 1_000)
        let now = staleDate.addingTimeInterval(
            HushwordTemporaryFileCleanup.staleAge + 1
        )
        let token = UUID().uuidString
        let staleNames = [
            "hushword-\(token).wav",
            "hushword-upload-\(token).multipart",
            "hushword-whisper-\(token).download",
            "hushword-ai-\(token).stdout",
        ]
        let staleDirectoryName = "hushword-codex-\(token)"
        let retainedNames = [
            "hushword-\(token).wav.backup",
            "hushword-not-a-uuid.wav",
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
            "hushword-\(UUID().uuidString).wav"
        )
        fileManager.createFile(atPath: recentURL.path, contents: Data([1]))
        try fileManager.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: recentURL.path
        )

        let removed = HushwordTemporaryFileCleanup.removeStaleFiles(
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
}
