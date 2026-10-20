import Foundation
import NaturalLanguage

package struct AppleCandidateSegmentEvidence: Equatable, Sendable {
    package let utf16Range: NSRange
    package let confidence: Float

    package init(utf16Range: NSRange, confidence: Float) {
        self.utf16Range = utf16Range
        self.confidence = confidence
    }
}

package struct AppleCandidateSemanticScore: Equatable, Sendable {
    package let sentenceRelevance: Double
    package let changedTermRelevance: Double

    package init(
        sentenceRelevance: Double,
        changedTermRelevance: Double
    ) {
        self.sentenceRelevance = sentenceRelevance
        self.changedTermRelevance = changedTermRelevance
    }
}

package enum AppleTranscriptionCandidateSelector {
    private static let maximumChangedSegmentConfidence: Float = 0.60
    private static let minimumSentenceGain = 0.012
    private static let minimumChangedTermGain = 0.02

    package static func select(
        candidates: [String],
        firstCandidateSegments: [AppleCandidateSegmentEvidence] = [],
        semanticScore: (
            _ candidate: String,
            _ changedTerm: String,
            _ context: String
        ) -> AppleCandidateSemanticScore? = AppleCandidateSemanticScorer.score
    ) -> String {
        let entries = uniqueEntries(candidates)
        guard let first = entries.first, entries.count > 1 else {
            return entries.first?.original ?? ""
        }

        var selected = first
        var selectedStrength = 1.0
        for candidate in entries.dropFirst() {
            guard let difference = comparableDifference(
                between: first.normalized,
                and: candidate.normalized
            ),
            firstCandidateSegments.contains(where: {
                $0.confidence < maximumChangedSegmentConfidence
                    && NSIntersectionRange(
                        $0.utf16Range,
                        difference.firstChangedRange
                    ).length > 0
            }),
            let firstScore = semanticScore(
                first.normalized,
                difference.firstChangedTerm,
                difference.context
            ),
            let candidateScore = semanticScore(
                candidate.normalized,
                difference.candidateChangedTerm,
                difference.context
            ) else {
                continue
            }

            let sentenceGain = candidateScore.sentenceRelevance
                - firstScore.sentenceRelevance
            let changedTermGain = candidateScore.changedTermRelevance
                - firstScore.changedTermRelevance
            guard sentenceGain >= minimumSentenceGain,
                  changedTermGain >= minimumChangedTermGain else {
                continue
            }

            let strength = min(
                sentenceGain / minimumSentenceGain,
                changedTermGain / minimumChangedTermGain
            )
            if strength > selectedStrength {
                selected = candidate
                selectedStrength = strength
            }
        }
        return selected.original
    }

    private struct Entry {
        let original: String
        let normalized: String
    }

    private struct Difference {
        let firstChangedTerm: String
        let candidateChangedTerm: String
        let context: String
        let firstChangedRange: NSRange
    }

    private static func uniqueEntries(_ candidates: [String]) -> [Entry] {
        var seen = Set<String>()
        return candidates.prefix(5).compactMap { original in
            let normalized = original.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return Entry(original: original, normalized: normalized)
        }
    }

    private static func comparableDifference(
        between first: String,
        and candidate: String
    ) -> Difference? {
        let firstCharacters = Array(first)
        let candidateCharacters = Array(candidate)
        var prefixCount = 0
        while prefixCount < min(
            firstCharacters.count,
            candidateCharacters.count
        ),
        firstCharacters[prefixCount] == candidateCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < min(
            firstCharacters.count - prefixCount,
            candidateCharacters.count - prefixCount
        ),
        firstCharacters[firstCharacters.count - suffixCount - 1]
            == candidateCharacters[candidateCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        let firstChanged = Array(
            firstCharacters[
                prefixCount..<(firstCharacters.count - suffixCount)
            ]
        )
        let candidateChanged = Array(
            candidateCharacters[
                prefixCount..<(candidateCharacters.count - suffixCount)
            ]
        )
        guard firstChanged.count == candidateChanged.count,
              (1...2).contains(firstChanged.count),
              firstChanged.allSatisfy(isHanCharacter),
              candidateChanged.allSatisfy(isHanCharacter) else {
            return nil
        }

        let prefix = String(firstCharacters[..<prefixCount])
        let suffix = String(
            firstCharacters[(firstCharacters.count - suffixCount)...]
        )
        let context = prefix + suffix
        guard context.filter(isHanCharacter).count >= 4 else { return nil }

        let firstChangedTerm = String(firstChanged)
        let candidateChangedTerm = String(candidateChanged)
        guard pronunciation(of: firstChangedTerm)
            == pronunciation(of: candidateChangedTerm) else {
            return nil
        }
        return Difference(
            firstChangedTerm: firstChangedTerm,
            candidateChangedTerm: candidateChangedTerm,
            context: context,
            firstChangedRange: NSRange(
                location: String(firstCharacters[..<prefixCount]).utf16.count,
                length: firstChangedTerm.utf16.count
            )
        )
    }

    private static func pronunciation(of text: String) -> String {
        let value = NSMutableString(string: text)
        CFStringTransform(value, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(value, nil, kCFStringTransformStripDiacritics, false)
        return (value as String)
            .lowercased()
            .filter { $0.isLetter }
    }

    private static func isHanCharacter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x323AF:
            return true
        default:
            return false
        }
    }
}

private enum AppleCandidateSemanticScorer {
    static func score(
        candidate: String,
        changedTerm: String,
        context: String
    ) -> AppleCandidateSemanticScore? {
        guard let sentenceEmbedding = NLEmbedding.sentenceEmbedding(
            for: .simplifiedChinese
        ),
        let wordEmbedding = NLEmbedding.wordEmbedding(
            for: .simplifiedChinese
        ) else {
            return nil
        }

        let sentenceDistance = Double(
            sentenceEmbedding.distance(between: candidate, and: context)
        )
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = context
        var changedTermDistances: [Double] = []
        tokenizer.enumerateTokens(
            in: context.startIndex..<context.endIndex
        ) { range, _ in
            let distance = Double(
                wordEmbedding.distance(
                    between: changedTerm,
                    and: String(context[range])
                )
            )
            if distance.isFinite, distance < 2 {
                changedTermDistances.append(distance)
            }
            return true
        }
        guard sentenceDistance.isFinite,
              !changedTermDistances.isEmpty else {
            return nil
        }
        return AppleCandidateSemanticScore(
            sentenceRelevance: -sentenceDistance,
            changedTermRelevance: -(
                changedTermDistances.reduce(0, +)
                    / Double(changedTermDistances.count)
            )
        )
    }
}
