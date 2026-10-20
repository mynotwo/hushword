import Foundation
import os

package enum RecognitionResultSource: String, Sendable {
    case whisper
    case apple
    case none

    package static func select(
        appleTranscript: String,
        whisperTranscript: String?,
        selectedTranscript: String
    ) -> Self {
        let apple = normalized(appleTranscript)
        let whisper = normalized(whisperTranscript)
        let selected = normalized(selectedTranscript)

        guard !selected.isEmpty else { return .none }
        if !whisper.isEmpty, selected == whisper {
            return .whisper
        }
        if !apple.isEmpty, selected == apple {
            return .apple
        }
        return .none
    }

    private static func normalized(_ transcript: String?) -> String {
        transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

package struct RecognitionTimingSnapshot: Equatable, Sendable {
    package let appleMilliseconds: Int64
    package let whisperMilliseconds: Int64?
    package let totalMilliseconds: Int64
    package let selectedSource: RecognitionResultSource
    package let appleWasEmpty: Bool
    package let whisperWasEmpty: Bool

    package init(
        appleMilliseconds: Int64,
        whisperMilliseconds: Int64?,
        totalMilliseconds: Int64,
        appleWasEmpty: Bool,
        whisperWasEmpty: Bool,
        selectedSource: RecognitionResultSource
    ) {
        self.appleMilliseconds = max(0, appleMilliseconds)
        self.whisperMilliseconds = whisperMilliseconds.map { max(0, $0) }
        self.totalMilliseconds = max(0, totalMilliseconds)
        self.selectedSource = selectedSource
        self.appleWasEmpty = appleWasEmpty
        self.whisperWasEmpty = whisperWasEmpty
    }

    package init(
        appleDuration: Duration,
        whisperDuration: Duration?,
        totalDuration: Duration,
        appleTranscript: String,
        whisperTranscript: String?,
        selectedTranscript: String
    ) {
        self.init(
            appleMilliseconds: Self.milliseconds(appleDuration),
            whisperMilliseconds: whisperDuration.map(Self.milliseconds),
            totalMilliseconds: Self.milliseconds(totalDuration),
            appleWasEmpty: Self.normalized(appleTranscript).isEmpty,
            whisperWasEmpty: Self.normalized(whisperTranscript).isEmpty,
            selectedSource: RecognitionResultSource.select(
                appleTranscript: appleTranscript,
                whisperTranscript: whisperTranscript,
                selectedTranscript: selectedTranscript
            )
        )
    }

    package var logMessage: String {
        let whisperValue = whisperMilliseconds.map(String.init) ?? "null"
        return [
            "recognition_timing",
            "apple_ms=\(appleMilliseconds)",
            "whisper_ms=\(whisperValue)",
            "total_ms=\(totalMilliseconds)",
            "selected=\(selectedSource.rawValue)",
            "apple_empty=\(appleWasEmpty)",
            "whisper_empty=\(whisperWasEmpty)",
        ].joined(separator: " ")
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            return 0
        }
        let (seconds, overflow) = components.seconds.multipliedReportingOverflow(
            by: 1_000
        )
        guard !overflow else { return Int64.max }
        let milliseconds = components.attoseconds / 1_000_000_000_000_000
        let (total, additionOverflow) = seconds.addingReportingOverflow(
            milliseconds
        )
        return additionOverflow ? Int64.max : total
    }

    private static func normalized(_ transcript: String?) -> String {
        transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

package enum RecognitionTimingLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.hushword",
        category: "RecognitionTiming"
    )

    package static func record(_ snapshot: RecognitionTimingSnapshot) {
        logger.notice("\(snapshot.logMessage, privacy: .public)")
    }
}
