import Foundation

enum ApplicationSupportDirectory {
    private static let legacyName = "FlowType"

    /// Returns `~/Library/Application Support/Hushword`, moving data left by
    /// the app's previous name into place the first time it is needed.
    static func url(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let current = root.appendingPathComponent("Hushword", isDirectory: true)
        let legacy = root.appendingPathComponent(legacyName, isDirectory: true)
        if !fileManager.fileExists(atPath: current.path),
           fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.moveItem(at: legacy, to: current)
        }
        return current
    }
}
