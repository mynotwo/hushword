import Combine
import Foundation

@MainActor
package final class WhisperModelManager: ObservableObject {
    package typealias ProgressReporter = @MainActor (Double) -> Void
    package typealias Downloader = (
        URL,
        @escaping ProgressReporter
    ) async throws -> URL

    @Published package private(set) var state: WhisperModelState
    @Published package private(set) var downloadProgress: Double?

    package let asset: WhisperModelAsset
    package let modelsDirectory: URL
    private let downloader: Downloader
    private var preparationTask: Task<Void, Never>?

    package init(
        asset: WhisperModelAsset = .distributionLargeV3TurboQ5(),
        modelsDirectory: URL = WhisperModelInstaller.modelsDirectory(),
        downloader: @escaping Downloader = WhisperModelManager.download
    ) {
        self.asset = asset
        self.modelsDirectory = modelsDirectory
        self.downloader = downloader
        state = WhisperModelInstaller.verifiedModelURL(
            asset: asset,
            modelsDirectory: modelsDirectory
        ) == nil ? .notInstalled : .ready
    }

    package func prepareIfNeeded() {
        guard state != .ready, preparationTask == nil else { return }
        preparationTask = Task { [weak self] in
            await self?.prepare()
            self?.preparationTask = nil
        }
    }

    package func prepare() async {
        if WhisperModelInstaller.verifiedModelURL(
            asset: asset,
            modelsDirectory: modelsDirectory
        ) != nil {
            state = .ready
            return
        }

        let installedURL = modelsDirectory.appendingPathComponent(asset.fileName)
        if FileManager.default.fileExists(atPath: installedURL.path) {
            state = .verifying
            let asset = asset
            let modelsDirectory = modelsDirectory
            do {
                _ = try await Task.detached(priority: .utility) {
                    try WhisperModelInstaller.verifyExistingModel(
                        asset: asset,
                        modelsDirectory: modelsDirectory
                    )
                }.value
                state = .ready
                return
            } catch {
                try? FileManager.default.removeItem(at: installedURL)
            }
        }

        state = .downloading
        downloadProgress = 0
        var downloadedURL: URL?
        do {
            let temporaryURL = try await downloader(
                asset.downloadURL
            ) { [weak self] progress in
                self?.downloadProgress = min(max(progress, 0), 1)
            }
            downloadedURL = temporaryURL
            downloadProgress = nil
            state = .verifying
            let asset = asset
            let modelsDirectory = modelsDirectory
            _ = try await Task.detached(priority: .utility) {
                try WhisperModelInstaller.installDownloadedFile(
                    at: temporaryURL,
                    asset: asset,
                    modelsDirectory: modelsDirectory
                )
            }.value
            state = .ready
        } catch {
            if let downloadedURL {
                try? FileManager.default.removeItem(at: downloadedURL)
            }
            downloadProgress = nil
            state = .failed(error.localizedDescription)
        }
    }

    package var statusText: String {
        switch state {
        case .notInstalled:
            return "Local model not installed · 574 MB"
        case .downloading:
            if let downloadProgress {
                return "Downloading local model · \(Int(downloadProgress * 100))%"
            }
            return "Downloading local model · 574 MB"
        case .verifying:
            return "Verifying local model…"
        case .ready:
            return "Local high-accuracy model ready"
        case .failed(let message):
            return "Apple Speech active · download failed: \(message)"
        }
    }

    private static func download(
        from remoteURL: URL,
        reportProgress: @escaping ProgressReporter
    ) async throws -> URL {
        let delegate = DownloadDelegate(reportProgress: reportProgress)
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        let (temporaryURL, response) = try await session.download(
            from: remoteURL
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.badServerResponse)
        }
        let retainedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-whisper-\(UUID().uuidString).download"
            )
        try FileManager.default.moveItem(
            at: temporaryURL,
            to: retainedURL
        )
        return retainedURL
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable {
    private let reportProgress: WhisperModelManager.ProgressReporter

    init(reportProgress: @escaping WhisperModelManager.ProgressReporter) {
        self.reportProgress = reportProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten)
            / Double(totalBytesExpectedToWrite)
        Task { @MainActor [reportProgress] in
            reportProgress(progress)
        }
    }
}
