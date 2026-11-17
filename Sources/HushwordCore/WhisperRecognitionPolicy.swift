import Foundation

public enum WhisperLanguagePolicy {
    public static func languageCode(for localeIdentifier: String) -> String {
        let language = localeIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased()
        switch language {
        case "zh", "en", "ja", "ko":
            return language ?? "auto"
        default:
            return "auto"
        }
    }
}

private enum WhisperPromptPolicy {
    static func prompt(contextualStrings: [String]) -> String {
        let terms = SpeechRecognitionVocabularyPolicy.normalizedTerms(
            contextualStrings
        )
        return (
            ["中文和 English 混合"] + terms
        ).joined(separator: ", ")
    }

    static func retryPrompt(contextualStrings: [String]) -> String {
        let terms = SpeechRecognitionVocabularyPolicy.normalizedTerms(
            contextualStrings
        )
        let expressions = [
            terms.containsCaseInsensitive("random signal")
                ? "使用 random signal" : nil,
            terms.containsCaseInsensitive("fine-tuning")
                ? "在 fine-tuning 的情况下达到类似结果" : nil,
            terms.containsCaseInsensitive("paper")
                ? "所以我们能发 paper 吗" : nil,
        ].compactMap { $0 }
        let names = [
            "meet criteria",
            "ByteDance",
            "Hushword",
            "Typeless",
        ].filter {
            $0 == "meet criteria"
                || terms.containsCaseInsensitive($0)
        }
        return "中文和 English 混合口语。常见表达："
            + expressions.joined(separator: "，")
            + (names.isEmpty ? "" : "；" + names.joined(separator: "；"))
            + "。"
    }
}

public enum WhisperRequestPolicy {
    public static func fields(
        localeIdentifier: String,
        contextualStrings: [String]
    ) -> [String: String] {
        [
            "language": WhisperLanguagePolicy.languageCode(
                for: localeIdentifier
            ),
            "beam_size": "1",
            "best_of": "1",
            "temperature": "0.0",
            "temperature_inc": "0.2",
            "no_speech_thold": "0.6",
            "response_format": "verbose_json",
            "prompt": WhisperPromptPolicy.prompt(
                contextualStrings: contextualStrings
            ),
        ]
    }

    public static func retryFields(
        localeIdentifier: String,
        contextualStrings: [String]
    ) -> [String: String] {
        var fields = fields(
            localeIdentifier: localeIdentifier,
            contextualStrings: contextualStrings
        )
        fields["prompt"] = WhisperPromptPolicy.retryPrompt(
            contextualStrings: contextualStrings
        )
        return fields
    }
}

public struct WhisperWordConfidence: Equatable, Sendable {
    public let text: String
    public let probability: Double

    public init(text: String, probability: Double) {
        self.text = text
        self.probability = min(max(probability, 0), 1)
    }
}

public struct WhisperTranscriptCandidate: Equatable, Sendable {
    public let text: String
    public let words: [WhisperWordConfidence]

    public init(text: String, words: [WhisperWordConfidence]) {
        self.text = text
        self.words = words
    }
}

public enum WhisperConfidenceRetryPolicy {
    private static let lowConfidenceThreshold = 0.55

    public static func shouldRetry(
        words: [WhisperWordConfidence]
    ) -> Bool {
        zip(words, words.dropFirst()).contains { first, second in
            first.probability < lowConfidenceThreshold
                && second.probability < lowConfidenceThreshold
        }
    }

    public static func select(
        primary: WhisperTranscriptCandidate,
        retry: WhisperTranscriptCandidate,
        contextualStrings: [String]
    ) -> WhisperTranscriptCandidate {
        let primaryText = normalizedContent(primary.text)
        let retryText = normalizedContent(retry.text)
        guard !primaryText.isEmpty,
              !retryText.isEmpty,
              retryAverageConfidence(retry.words)
                > retryAverageConfidence(primary.words),
              terminologyHits(
                  in: retry.text,
                  contextualStrings: contextualStrings
              ) > terminologyHits(
                  in: primary.text,
                  contextualStrings: contextualStrings
              ),
              editDistance(primaryText, retryText)
                <= maximumSafeDistance(
                    primaryCount: primaryText.count,
                    retryCount: retryText.count
                ) else {
            return primary
        }
        return retry
    }

    private static func retryAverageConfidence(
        _ words: [WhisperWordConfidence]
    ) -> Double {
        guard !words.isEmpty else { return 0 }
        return words.reduce(0) { $0 + $1.probability }
            / Double(words.count)
    }

    private static func terminologyHits(
        in text: String,
        contextualStrings: [String]
    ) -> Int {
        SpeechRecognitionVocabularyPolicy.normalizedTerms(contextualStrings)
            .reduce(into: 0) { count, term in
                if text.localizedCaseInsensitiveContains(term) {
                    count += 1
                }
            }
    }

    private static func normalizedContent(_ text: String) -> [Character] {
        Array(text.lowercased().filter {
            $0.isLetter || $0.isNumber
        })
    }

    private static func maximumSafeDistance(
        primaryCount: Int,
        retryCount: Int
    ) -> Int {
        max(4, Int(Double(max(primaryCount, retryCount)) * 0.45))
    }

    private static func editDistance(
        _ lhs: [Character],
        _ rhs: [Character]
    ) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = lhsIndex + 1
            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                current[rhsIndex + 1] = min(
                    previous[rhsIndex + 1] + 1,
                    current[rhsIndex] + 1,
                    previous[rhsIndex] + (
                        lhsCharacter == rhsCharacter ? 0 : 1
                    )
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }
}

private extension Array where Element == String {
    func containsCaseInsensitive(_ value: String) -> Bool {
        contains {
            $0.caseInsensitiveCompare(value) == .orderedSame
        }
    }
}

public enum WhisperCommandPolicy {
    public static func arguments(
        modelPath: String,
        audioPath: String,
        localeIdentifier: String,
        contextualStrings: [String]
    ) -> [String] {
        return [
            "-m", modelPath,
            "-f", audioPath,
            "-l", WhisperLanguagePolicy.languageCode(
                for: localeIdentifier
            ),
            "-nt",
            "-np",
            "-t", "8",
            "-bo", "1",
            "-bs", "1",
            "--prompt", WhisperPromptPolicy.prompt(
                contextualStrings: contextualStrings
            ),
        ]
    }
}

public enum WhisperModelPolicy {
    public static let preferredModelNames = [
        "ggml-large-v3-turbo-q5_0.bin",
        "ggml-large-v3-turbo-q8_0.bin",
        "ggml-large-v3-turbo.bin",
    ]
}

public enum WhisperServerPolicy {
    public static func arguments(
        modelPath: String,
        port: Int,
        contextualStrings: [String]
    ) -> [String] {
        return [
            "-m", modelPath,
            "--host", "127.0.0.1",
            "--port", String(port),
            "-l", "auto",
            "-t", "8",
            "-bo", "5",
            "-bs", "5",
            "-nt",
            "--prompt", WhisperPromptPolicy.prompt(
                contextualStrings: contextualStrings
            ),
        ]
    }
}

public enum BilingualFinalizationPolicy {
    public static func shouldRun(
        executableExists: Bool,
        modelExists: Bool,
        recordingHasAudio: Bool
    ) -> Bool {
        executableExists && modelExists && recordingHasAudio
    }
}
