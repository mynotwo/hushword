import Foundation

public struct LearnedCorrection: Codable, Equatable, Sendable {
    public let observed: String
    public let preferred: String

    public init(observed: String, preferred: String) {
        self.observed = observed
        self.preferred = preferred
    }
}

public enum CorrectionMemoryPolicy {
    public static func infer(
        originalText: String,
        editedText: String,
        insertedRange: NSRange
    ) -> LearnedCorrection? {
        let original = originalText as NSString
        let edited = editedText as NSString
        guard insertedRange.location != NSNotFound,
              insertedRange.location >= 0,
              insertedRange.length > 0,
              NSMaxRange(insertedRange) <= original.length,
              let fullDifference = difference(
                  originalText,
                  editedText
              ),
              NSIntersectionRange(
                  fullDifference.originalRange,
                  insertedRange
              ) == fullDifference.originalRange else {
            return nil
        }

        let editedInsertedLength = insertedRange.length
            + edited.length
            - original.length
        let editedInsertedRange = NSRange(
            location: insertedRange.location,
            length: editedInsertedLength
        )
        guard editedInsertedLength > 0,
              NSMaxRange(editedInsertedRange) <= edited.length else {
            return nil
        }

        let originalInserted = original.substring(with: insertedRange)
        let editedInserted = edited.substring(with: editedInsertedRange)
        guard let localDifference = difference(
            originalInserted,
            editedInserted
        ) else {
            return nil
        }

        if let technical = technicalCorrection(
            original: originalInserted,
            edited: editedInserted,
            difference: localDifference
        ) {
            return technical
        }
        return contextualHomophoneCorrection(
            original: originalInserted,
            edited: editedInserted,
            difference: localDifference
        )
    }

    public static func updating(
        _ correction: LearnedCorrection,
        in corrections: [LearnedCorrection],
        manualDictionaryText: String,
        maximumCount: Int = 50
    ) -> [LearnedCorrection] {
        let observed = correction.observed.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let preferred = correction.preferred.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !observed.isEmpty,
              !preferred.isEmpty,
              observed.caseInsensitiveCompare(preferred) != .orderedSame else {
            return corrections
        }

        let manualKeys = manualDictionaryText
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(
                    separator: "=",
                    maxSplits: 1
                )
                guard parts.count == 2 else { return nil }
                return parts[0].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
        guard !manualKeys.contains(where: {
            $0.caseInsensitiveCompare(observed) == .orderedSame
        }) else {
            return corrections
        }

        let learned = LearnedCorrection(
            observed: observed,
            preferred: preferred
        )
        let remaining = corrections.filter {
            $0.observed.caseInsensitiveCompare(observed) != .orderedSame
        }
        return Array(([learned] + remaining).prefix(max(0, maximumCount)))
    }

    private struct Difference {
        let originalRange: NSRange
        let editedRange: NSRange
        let originalCharacters: Range<Int>
        let editedCharacters: Range<Int>
    }

    private static func difference(
        _ original: String,
        _ edited: String
    ) -> Difference? {
        guard original != edited else { return nil }
        let originalCharacters = Array(original)
        let editedCharacters = Array(edited)
        var prefixCount = 0
        while prefixCount < min(
            originalCharacters.count,
            editedCharacters.count
        ),
        originalCharacters[prefixCount] == editedCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < min(
            originalCharacters.count - prefixCount,
            editedCharacters.count - prefixCount
        ),
        originalCharacters[originalCharacters.count - suffixCount - 1]
            == editedCharacters[editedCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        let originalCharacterRange: Range<Int> =
            prefixCount..<(originalCharacters.count - suffixCount)
        let editedCharacterRange: Range<Int> =
            prefixCount..<(editedCharacters.count - suffixCount)
        let originalPrefix = String(
            originalCharacters[..<originalCharacterRange.lowerBound]
        )
        let editedPrefix = String(
            editedCharacters[..<editedCharacterRange.lowerBound]
        )
        let originalChanged = String(
            originalCharacters[originalCharacterRange]
        )
        let editedChanged = String(
            editedCharacters[editedCharacterRange]
        )
        return Difference(
            originalRange: NSRange(
                location: originalPrefix.utf16.count,
                length: originalChanged.utf16.count
            ),
            editedRange: NSRange(
                location: editedPrefix.utf16.count,
                length: editedChanged.utf16.count
            ),
            originalCharacters: originalCharacterRange,
            editedCharacters: editedCharacterRange
        )
    }

    private static func contextualHomophoneCorrection(
        original: String,
        edited: String,
        difference: Difference
    ) -> LearnedCorrection? {
        let originalCharacters = Array(original)
        let editedCharacters = Array(edited)
        let observed = String(
            originalCharacters[difference.originalCharacters]
        )
        let preferred = String(
            editedCharacters[difference.editedCharacters]
        )
        guard !observed.isEmpty,
              observed.count == preferred.count,
              observed.count <= 2,
              observed.allSatisfy(isHanCharacter),
              preferred.allSatisfy(isHanCharacter),
              pronunciation(of: observed) == pronunciation(of: preferred) else {
            return nil
        }

        let contextStart = max(
            0,
            difference.originalCharacters.lowerBound - 2
        )
        let contextEnd = min(
            originalCharacters.count,
            difference.originalCharacters.upperBound + 2
        )
        let editedContextEnd = min(
            editedCharacters.count,
            difference.editedCharacters.upperBound
                + (contextEnd - difference.originalCharacters.upperBound)
        )
        let observedPhrase = String(
            originalCharacters[contextStart..<contextEnd]
        )
        let preferredPhrase = String(
            editedCharacters[contextStart..<editedContextEnd]
        )
        guard observedPhrase.count > observed.count,
              observedPhrase.count == preferredPhrase.count else {
            return nil
        }
        return LearnedCorrection(
            observed: observedPhrase,
            preferred: preferredPhrase
        )
    }

    private static func technicalCorrection(
        original: String,
        edited: String,
        difference: Difference
    ) -> LearnedCorrection? {
        let originalCharacters = Array(original)
        let editedCharacters = Array(edited)
        let originalRange = technicalTermRange(
            in: originalCharacters,
            around: difference.originalCharacters
        )
        let editedRange = technicalTermRange(
            in: editedCharacters,
            around: difference.editedCharacters
        )
        let observed = String(originalCharacters[originalRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = String(editedCharacters[editedRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObserved = normalizedTechnicalTerm(observed)
        let normalizedPreferred = normalizedTechnicalTerm(preferred)
        guard observed != preferred,
              !normalizedObserved.isEmpty,
              normalizedObserved == normalizedPreferred,
              normalizedObserved.count >= 3,
              observed.count <= 32,
              preferred.count <= 32,
              observed.contains(where: isASCIILetter),
              preferred.contains(where: isASCIILetter) else {
            return nil
        }
        return LearnedCorrection(
            observed: observed,
            preferred: preferred
        )
    }

    private static func technicalTermRange(
        in characters: [Character],
        around changedRange: Range<Int>
    ) -> Range<Int> {
        var lowerBound = changedRange.lowerBound
        var upperBound = changedRange.upperBound
        while lowerBound > 0,
              isTechnicalTermCharacter(characters[lowerBound - 1]) {
            lowerBound -= 1
        }
        while upperBound < characters.count,
              isTechnicalTermCharacter(characters[upperBound]) {
            upperBound += 1
        }
        return lowerBound..<upperBound
    }

    private static func normalizedTechnicalTerm(_ value: String) -> String {
        value.lowercased().filter {
            $0.isLetter || $0.isNumber
        }
    }

    private static func isTechnicalTermCharacter(
        _ character: Character
    ) -> Bool {
        isASCIILetter(character)
            || character.unicodeScalars.allSatisfy {
                (48...57).contains($0.value)
            }
            || character.isWhitespace
            || character == "-"
            || character == "."
    }

    private static func pronunciation(of text: String) -> String {
        let value = NSMutableString(string: text)
        CFStringTransform(
            value,
            nil,
            kCFStringTransformMandarinLatin,
            false
        )
        CFStringTransform(
            value,
            nil,
            kCFStringTransformStripDiacritics,
            false
        )
        return (value as String)
            .lowercased()
            .filter(\.isLetter)
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

    private static func isASCIILetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (65...90).contains($0.value)
                || (97...122).contains($0.value)
        }
    }
}
