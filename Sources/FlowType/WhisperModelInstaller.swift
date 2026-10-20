import CryptoKit
import Foundation

package enum WhisperModelInstallationError: LocalizedError {
    case unexpectedByteCount(expected: Int64, actual: Int64)
    case checksumMismatch

    package var errorDescription: String? {
        switch self {
        case .unexpectedByteCount(let expected, let actual):
            return "Model download size mismatch (expected \(expected), got \(actual))."
        case .checksumMismatch:
            return "Model download checksum verification failed."
        }
    }
}

package enum WhisperModelInstaller {
    private struct VerificationMarker: Codable {
        let sha256: String
        let byteCount: Int64
        let modificationTime: TimeInterval
    }

    package static func installDownloadedFile(
        at downloadedURL: URL,
        asset: WhisperModelAsset,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let attributes = try fileManager.attributesOfItem(
            atPath: downloadedURL.path
        )
        let actualByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualByteCount == asset.expectedByteCount else {
            throw WhisperModelInstallationError.unexpectedByteCount(
                expected: asset.expectedByteCount,
                actual: actualByteCount
            )
        }
        guard try sha256(of: downloadedURL) == asset.sha256.lowercased() else {
            throw WhisperModelInstallationError.checksumMismatch
        }

        try fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        let installedURL = modelsDirectory.appendingPathComponent(asset.fileName)
        let stagedURL = modelsDirectory.appendingPathComponent(
            ".\(asset.fileName).\(UUID().uuidString).staging"
        )
        do {
            try fileManager.moveItem(at: downloadedURL, to: stagedURL)
            if fileManager.fileExists(atPath: installedURL.path) {
                _ = try fileManager.replaceItemAt(
                    installedURL,
                    withItemAt: stagedURL
                )
            } else {
                try fileManager.moveItem(at: stagedURL, to: installedURL)
            }
            try writeVerificationMarker(
                for: installedURL,
                asset: asset,
                fileManager: fileManager
            )
            return installedURL
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }

    package static func verifiedModelURL(
        asset: WhisperModelAsset,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let installedURL = modelsDirectory.appendingPathComponent(asset.fileName)
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: installedURL.path
        ),
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value,
        byteCount == asset.expectedByteCount,
        let modificationDate = attributes[.modificationDate] as? Date,
        let markerData = try? Data(
            contentsOf: verificationMarkerURL(for: installedURL)
        ),
        let marker = try? JSONDecoder().decode(
            VerificationMarker.self,
            from: markerData
        ),
        marker.sha256 == asset.sha256.lowercased(),
        marker.byteCount == byteCount,
        marker.modificationTime == modificationDate.timeIntervalSince1970 else {
            return nil
        }
        return installedURL
    }

    package static func verifyExistingModel(
        asset: WhisperModelAsset,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let installedURL = modelsDirectory.appendingPathComponent(asset.fileName)
        let attributes = try fileManager.attributesOfItem(
            atPath: installedURL.path
        )
        let actualByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualByteCount == asset.expectedByteCount else {
            throw WhisperModelInstallationError.unexpectedByteCount(
                expected: asset.expectedByteCount,
                actual: actualByteCount
            )
        }
        guard try sha256(of: installedURL) == asset.sha256.lowercased() else {
            throw WhisperModelInstallationError.checksumMismatch
        }
        try writeVerificationMarker(
            for: installedURL,
            asset: asset,
            fileManager: fileManager
        )
        return installedURL
    }

    package static func isInstalledModelValid(
        asset: WhisperModelAsset,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let installedURL = modelsDirectory.appendingPathComponent(asset.fileName)
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: installedURL.path
        ),
        (attributes[.size] as? NSNumber)?.int64Value
            == asset.expectedByteCount else {
            return false
        }
        return (try? sha256(of: installedURL)) == asset.sha256.lowercased()
    }

    package static func modelsDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("FlowType", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
    }

    private static func writeVerificationMarker(
        for installedURL: URL,
        asset: WhisperModelAsset,
        fileManager: FileManager
    ) throws {
        let attributes = try fileManager.attributesOfItem(
            atPath: installedURL.path
        )
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast
        let marker = VerificationMarker(
            sha256: asset.sha256.lowercased(),
            byteCount: byteCount,
            modificationTime: modificationDate.timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(
            to: verificationMarkerURL(for: installedURL),
            options: .atomic
        )
    }

    private static func verificationMarkerURL(for installedURL: URL) -> URL {
        installedURL.appendingPathExtension("verified.json")
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }

        var hasher = SHA256()
        while true {
            let data = try file.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }
}
