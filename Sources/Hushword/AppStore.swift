import HushwordCore
import Foundation

package struct AppStore {
    private let customDirectory: URL?

    package init(directory: URL? = nil) {
        customDirectory = directory
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var directory: URL {
        if let customDirectory {
            return customDirectory
        }
        return ApplicationSupportDirectory.url()
    }

    func loadSettings() -> AppSettings {
        load(AppSettings.self, from: "settings.json") ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        save(settings, to: "settings.json")
    }

    func loadHistory() -> [HistoryItem] {
        load([HistoryItem].self, from: "history.json") ?? []
    }

    func saveHistory(_ history: [HistoryItem]) {
        save(history, to: "history.json")
    }

    package func loadLearnedCorrections() -> [LearnedCorrection] {
        load(
            [LearnedCorrection].self,
            from: "learned-corrections.json"
        ) ?? []
    }

    package func saveLearnedCorrections(
        _ corrections: [LearnedCorrection]
    ) {
        save(corrections, to: "learned-corrections.json")
    }

    private func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to fileName: String) {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(
            to: directory.appendingPathComponent(fileName),
            options: .atomic
        )
    }
}
