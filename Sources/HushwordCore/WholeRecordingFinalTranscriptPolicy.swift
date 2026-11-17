import Foundation

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
