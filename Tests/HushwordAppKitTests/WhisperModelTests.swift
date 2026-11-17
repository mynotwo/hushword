import HushwordCore
import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    @MainActor
    static func pinsOfficialLargeV3TurboQ5Asset() async throws {
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

    static func usesReleaseModelMirrorFromBundleMetadata() async throws {
        let asset = WhisperModelAsset.distributionLargeV3TurboQ5(
            infoDictionary: [
                "HushwordWhisperModelURL":
                    "https://downloads.example.com/models/hushword-q5.bin",
            ]
        )
        guard asset.downloadURL.absoluteString
                == "https://downloads.example.com/models/hushword-q5.bin",
              asset.expectedByteCount
                == WhisperModelAsset.largeV3TurboQ5.expectedByteCount,
              asset.sha256 == WhisperModelAsset.largeV3TurboQ5.sha256 else {
            throw TestFailure(
                description: "release metadata did not preserve the pinned model identity"
            )
        }
    }

    @MainActor
    static func usesAppleRecognitionWhileWhisperModelIsUnavailable() async throws {
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
    static func prefersBundledWhisperRuntime() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushword-runtime-test-\(UUID().uuidString)")
        let appURL = root.appendingPathComponent("Hushword.app", isDirectory: true)
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
    static func atomicallyInstallsVerifiedWhisperModel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushword-model-install-\(UUID().uuidString)")
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
    static func preservesInstalledModelWhenVerificationFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushword-model-reject-\(UUID().uuidString)")
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
    static func marksVerifiedWhisperModelAsRuntimeReady() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushword-model-marker-\(UUID().uuidString)")
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
    static func downloadsAndPreparesWhisperModelInBackground() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushword-model-manager-\(UUID().uuidString)")
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
    static func reportsModelDownloadProgressAndRetriesFailures() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hushword-model-progress-\(UUID().uuidString)")
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
}
