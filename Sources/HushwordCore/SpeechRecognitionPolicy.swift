import Foundation

public struct SpeechRecognitionPolicy: Sendable {
    public let requiresOnDeviceRecognition: Bool
    public let addsPunctuation: Bool

    public static let highAccuracy = SpeechRecognitionPolicy(
        requiresOnDeviceRecognition: false,
        addsPunctuation: true
    )
}

public enum SpeechRecognitionVocabularyPolicy {
    public static func normalizedTerms(
        _ terms: [String],
        maximumCount: Int = 100
    ) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for term in terms {
            let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else {
                continue
            }
            normalized.append(value)
            if normalized.count == max(0, maximumCount) {
                break
            }
        }
        return normalized
    }
}

public enum AppleFinalizationPolicy {
    public static let wholeRecordingTimeoutNanoseconds: UInt64 = 30_000_000_000
}
