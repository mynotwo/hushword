import Foundation

package enum HushwordTemporaryFileCleanup {
    package static let staleAge: TimeInterval = 6 * 60 * 60

    package static func schedule() {
        DispatchQueue.global(qos: .utility).async {
            for directory in defaultDirectories() {
                _ = removeStaleFiles(in: directory)
            }
        }
    }

    package static func defaultDirectories(
        fileManager: FileManager = .default
    ) -> [URL] {
        let directories = [
            fileManager.temporaryDirectory,
            URL(fileURLWithPath: "/tmp", isDirectory: true),
        ]
        var paths = Set<String>()
        return directories.filter {
            paths.insert($0.standardizedFileURL.path).inserted
        }
    }

    @discardableResult
    package static func removeStaleFiles(
        in directory: URL = FileManager.default.temporaryDirectory,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var removed: [URL] = []
        for file in files where matches(file.lastPathComponent) {
            let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            guard let modifiedAt = values?.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > staleAge else {
                continue
            }
            do {
                try fileManager.removeItem(at: file)
                removed.append(file)
            } catch {
                continue
            }
        }
        return removed
    }

    private static func matches(_ fileName: String) -> Bool {
        let codexPrefix = "hushword-codex-"
        if fileName.hasPrefix(codexPrefix) {
            let token = String(fileName.dropFirst(codexPrefix.count))
            return UUID(uuidString: token) != nil
        }

        let formats: [(prefix: String, suffixes: [String])] = [
            ("hushword-", [".wav"]),
            ("hushword-upload-", [".multipart"]),
            ("hushword-whisper-", [".download"]),
            ("hushword-ai-", [".txt", ".stdout", ".stderr"]),
        ]
        for format in formats where fileName.hasPrefix(format.prefix) {
            guard let suffix = format.suffixes.first(where: fileName.hasSuffix)
            else {
                continue
            }
            let tokenStart = fileName.index(
                fileName.startIndex,
                offsetBy: format.prefix.count
            )
            let tokenEnd = fileName.index(
                fileName.endIndex,
                offsetBy: -suffix.count
            )
            guard tokenStart < tokenEnd else { continue }
            return UUID(uuidString: String(fileName[tokenStart..<tokenEnd])) != nil
        }
        return false
    }
}
