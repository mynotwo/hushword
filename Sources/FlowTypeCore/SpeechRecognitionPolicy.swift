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
            "FlowType",
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

public enum WholeRecordingFinalTranscriptPolicy {
    public static func select(
        whisperTranscript: String?,
        appleTranscript: String,
        contextualStrings: [String]
    ) -> String {
        let apple = normalized(appleTranscript)
        let whisper = normalized(whisperTranscript)
        if isLikelyTruncated(
            candidate: apple,
            comparedWith: whisper
        ) {
            return whisper
        }
        return selectRecognitionCandidate(
            whisper: whisper,
            apple: apple,
            contextualStrings: contextualStrings
        )
    }

    private static func selectRecognitionCandidate(
        whisper: String,
        apple: String,
        contextualStrings: [String]
    ) -> String {
        guard !whisper.isEmpty else { return apple }
        guard !apple.isEmpty else { return whisper }

        let terms = SpeechRecognitionVocabularyPolicy.normalizedTerms(
            contextualStrings
        )
        let whisperHits = terminologyHits(in: whisper, terms: terms)
        let appleHits = terminologyHits(in: apple, terms: terms)
        if whisperHits != appleHits {
            return whisperHits > appleHits
                ? borrowingPunctuation(from: apple, for: whisper)
                : apple
        }

        let whisperContainsLatin = containsLatinLetters(whisper)
        let appleContainsLatin = containsLatinLetters(apple)
        if whisperContainsLatin || appleContainsLatin {
            return borrowingPunctuation(from: apple, for: whisper)
        }
        return apple
    }

    private static func isLikelyTruncated(
        candidate: String,
        comparedWith reference: String
    ) -> Bool {
        guard !candidate.isEmpty, !reference.isEmpty else { return false }
        let candidateContent = contentCharacters(in: candidate)
        let referenceContent = contentCharacters(in: reference)
        guard referenceContent.count >= candidateContent.count + 6 else {
            return false
        }
        let threshold = Int(Double(referenceContent.count) * 0.82)
        guard candidateContent.count < threshold else { return false }
        return referenceContent.starts(with: candidateContent)
    }

    private static func contentCharacters(in text: String) -> [Character] {
        text.filter {
            !$0.isWhitespace && !transferablePunctuation.contains($0)
        }
    }

    private static let transferablePunctuation: Set<Character> = [
        "，", "。", "！", "？", "：", "；",
        ",", ".", "!", "?", ":", ";",
    ]

    private struct PunctuationLayout {
        let alignmentCharacters: [Character]
        let punctuationByBoundary: [Int: String]
    }

    private enum AlignmentStep {
        case both
        case sourceOnly
        case guideOnly
    }

    private static func borrowingPunctuation(
        from guide: String,
        for source: String
    ) -> String {
        let sourceLayout = punctuationLayout(for: source)
        let guideLayout = punctuationLayout(for: guide)
        let guideHasMorePunctuation = guideLayout.punctuationByBoundary.count
            > sourceLayout.punctuationByBoundary.count
        let guideHasMoreSentenceBoundaries = sentenceBoundaryCount(
            in: guideLayout
        ) > sentenceBoundaryCount(in: sourceLayout)
        guard guideHasMorePunctuation || guideHasMoreSentenceBoundaries,
              !sourceLayout.alignmentCharacters.isEmpty,
              !guideLayout.alignmentCharacters.isEmpty else {
            return source
        }

        let alignment = alignmentBoundaries(
            source: sourceLayout.alignmentCharacters,
            guide: guideLayout.alignmentCharacters
        )
        let maximumLength = max(
            sourceLayout.alignmentCharacters.count,
            guideLayout.alignmentCharacters.count
        )
        guard alignment.distance
                <= max(2, Int(Double(maximumLength) * 0.28)) else {
            return source
        }

        var punctuation = sourceLayout.punctuationByBoundary
        for (guideBoundary, value) in guideLayout.punctuationByBoundary {
            let sourceBoundary = alignment.guideToSource[guideBoundary]
            punctuation[sourceBoundary] = value
        }
        return applying(punctuation: punctuation, to: source)
    }

    private static func sentenceBoundaryCount(
        in layout: PunctuationLayout
    ) -> Int {
        layout.punctuationByBoundary.values.reduce(into: 0) {
            count,
            punctuation in
            if punctuation.contains(where: {
                sentenceBoundaryPunctuation.contains($0)
            }) {
                count += 1
            }
        }
    }

    private static let sentenceBoundaryPunctuation: Set<Character> = [
        "。", "！", "？", ".", "!", "?",
    ]

    private static func punctuationLayout(
        for text: String
    ) -> PunctuationLayout {
        var alignmentCharacters: [Character] = []
        var punctuationByBoundary: [Int: String] = [:]

        for character in text {
            if transferablePunctuation.contains(character) {
                punctuationByBoundary[
                    alignmentCharacters.count,
                    default: ""
                ].append(character)
            } else if !character.isWhitespace {
                alignmentCharacters.append(character)
            }
        }
        return PunctuationLayout(
            alignmentCharacters: alignmentCharacters,
            punctuationByBoundary: punctuationByBoundary
        )
    }

    private static func alignmentBoundaries(
        source: [Character],
        guide: [Character]
    ) -> (distance: Int, guideToSource: [Int]) {
        let rowWidth = guide.count + 1
        var distances = Array(
            repeating: 0,
            count: (source.count + 1) * rowWidth
        )

        for sourceIndex in 0...source.count {
            distances[sourceIndex * rowWidth] = sourceIndex
        }
        for guideIndex in 0...guide.count {
            distances[guideIndex] = guideIndex
        }
        if !source.isEmpty, !guide.isEmpty {
            for sourceIndex in 1...source.count {
                for guideIndex in 1...guide.count {
                    let substitutionCost = charactersMatch(
                        source[sourceIndex - 1],
                        guide[guideIndex - 1]
                    ) ? 0 : 1
                    let offset = sourceIndex * rowWidth + guideIndex
                    distances[offset] = min(
                        distances[offset - rowWidth - 1] + substitutionCost,
                        distances[offset - rowWidth] + 1,
                        distances[offset - 1] + 1
                    )
                }
            }
        }

        var sourceIndex = source.count
        var guideIndex = guide.count
        var reversedSteps: [AlignmentStep] = []
        while sourceIndex > 0 || guideIndex > 0 {
            let offset = sourceIndex * rowWidth + guideIndex
            if sourceIndex > 0, guideIndex > 0 {
                let substitutionCost = charactersMatch(
                    source[sourceIndex - 1],
                    guide[guideIndex - 1]
                ) ? 0 : 1
                if distances[offset]
                    == distances[offset - rowWidth - 1] + substitutionCost {
                    reversedSteps.append(.both)
                    sourceIndex -= 1
                    guideIndex -= 1
                    continue
                }
            }
            if sourceIndex > 0,
               distances[offset] == distances[offset - rowWidth] + 1 {
                reversedSteps.append(.sourceOnly)
                sourceIndex -= 1
            } else {
                reversedSteps.append(.guideOnly)
                guideIndex -= 1
            }
        }

        sourceIndex = 0
        guideIndex = 0
        var guideToSource = Array(repeating: 0, count: guide.count + 1)
        for step in reversedSteps.reversed() {
            switch step {
            case .both:
                sourceIndex += 1
                guideIndex += 1
                guideToSource[guideIndex] = sourceIndex
            case .sourceOnly:
                sourceIndex += 1
                guideToSource[guideIndex] = sourceIndex
            case .guideOnly:
                guideIndex += 1
                guideToSource[guideIndex] = sourceIndex
            }
        }
        return (
            distances[source.count * rowWidth + guide.count],
            guideToSource
        )
    }

    private static func applying(
        punctuation: [Int: String],
        to source: String
    ) -> String {
        var output = punctuation[0] ?? ""
        var boundary = 0
        for character in source {
            guard !transferablePunctuation.contains(character) else {
                continue
            }
            output.append(character)
            if !character.isWhitespace {
                boundary += 1
                output += punctuation[boundary] ?? ""
            }
        }
        return output
    }

    private static func charactersMatch(
        _ lhs: Character,
        _ rhs: Character
    ) -> Bool {
        String(lhs).caseInsensitiveCompare(String(rhs)) == .orderedSame
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func containsLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.letters.contains($0)
                && $0.value < 128
        }
    }

    private static func terminologyHits(
        in text: String,
        terms: [String]
    ) -> Int {
        terms.reduce(into: 0) { count, term in
            if text.localizedCaseInsensitiveContains(term) {
                count += 1
            }
        }
    }
}

