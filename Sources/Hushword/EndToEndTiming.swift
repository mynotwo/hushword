import Foundation
import os

package enum EndToEndTimingOutcome: String, Codable, Sendable {
    case pasted
    case copied
    case noText
    case failed
}

package struct EndToEndTimingRecord: Codable, Equatable, Sendable {
    package let startToListeningMilliseconds: Int64?
    package let stopToRecognitionReadyMilliseconds: Int64?
    package let targetActivationMilliseconds: Int64?
    package let pasteMilliseconds: Int64?
    package let stopToTextDeliveredMilliseconds: Int64?
    package let autoPaste: Bool
    package let outcome: EndToEndTimingOutcome

    package init(
        startToListeningMilliseconds: Int64?,
        stopToRecognitionReadyMilliseconds: Int64?,
        targetActivationMilliseconds: Int64?,
        pasteMilliseconds: Int64?,
        stopToTextDeliveredMilliseconds: Int64?,
        autoPaste: Bool,
        outcome: EndToEndTimingOutcome
    ) {
        self.startToListeningMilliseconds = Self.clamped(
            startToListeningMilliseconds
        )
        self.stopToRecognitionReadyMilliseconds = Self.clamped(
            stopToRecognitionReadyMilliseconds
        )
        self.targetActivationMilliseconds = Self.clamped(
            targetActivationMilliseconds
        )
        self.pasteMilliseconds = Self.clamped(pasteMilliseconds)
        self.stopToTextDeliveredMilliseconds = Self.clamped(
            stopToTextDeliveredMilliseconds
        )
        self.autoPaste = autoPaste
        self.outcome = outcome
    }

    private static func clamped(_ value: Int64?) -> Int64? {
        value.map { max(0, $0) }
    }
}

package final class EndToEndTimingStore: @unchecked Sendable {
    package static let maximumRecords = 100

    private let fileURL: URL
    private let queue = DispatchQueue(
        label: "com.local.hushword.end-to-end-timing",
        qos: .utility
    )

    package init(fileURL: URL = EndToEndTimingStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    package static func trimmedRecords(
        _ records: [EndToEndTimingRecord]
    ) -> [EndToEndTimingRecord] {
        Array(records.suffix(maximumRecords))
    }

    func enqueue(_ record: EndToEndTimingRecord) {
        queue.async {
            EndToEndTimingLogger.record(record)
            self.appendToDisk(record)
        }
    }

    private func loadRecordsFromDisk() -> [EndToEndTimingRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode(
                [EndToEndTimingRecord].self,
                from: data
              ) else {
            return []
        }
        return Self.trimmedRecords(records)
    }

    private func appendToDisk(_ record: EndToEndTimingRecord) {
        let records = Self.trimmedRecords(loadRecordsFromDisk() + [record])
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            EndToEndTimingLogger.recordPersistenceFailure()
        }
    }

    private static var defaultFileURL: URL {
        return ApplicationSupportDirectory.url()
            .appendingPathComponent("end-to-end-timing.json")
    }
}

package enum EndToEndTimingLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.hushword",
        category: "EndToEndTiming"
    )

    package static func record(_ record: EndToEndTimingRecord) {
        logger.notice(
            """
            end_to_end_timing \
            start_to_listening_ms=\(value(record.startToListeningMilliseconds), privacy: .public) \
            stop_to_recognition_ready_ms=\(value(record.stopToRecognitionReadyMilliseconds), privacy: .public) \
            target_activation_ms=\(value(record.targetActivationMilliseconds), privacy: .public) \
            paste_ms=\(value(record.pasteMilliseconds), privacy: .public) \
            stop_to_text_delivered_ms=\(value(record.stopToTextDeliveredMilliseconds), privacy: .public) \
            auto_paste=\(record.autoPaste, privacy: .public) \
            outcome=\(record.outcome.rawValue, privacy: .public)
            """
        )
    }

    static func recordPersistenceFailure() {
        logger.error("end_to_end_timing persistence_failed=true")
    }

    private static func value(_ value: Int64?) -> String {
        value.map(String.init) ?? "null"
    }
}
