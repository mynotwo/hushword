import CoreGraphics
import Foundation

package struct ReplacementInteractionSnapshot: Equatable, Sendable {
    package let keyDownCount: UInt32
    package let leftMouseDownCount: UInt32
    package let rightMouseDownCount: UInt32
    package let otherMouseDownCount: UInt32
    package let scrollWheelCount: UInt32

    package init(
        keyDownCount: UInt32,
        leftMouseDownCount: UInt32,
        rightMouseDownCount: UInt32,
        otherMouseDownCount: UInt32,
        scrollWheelCount: UInt32
    ) {
        self.keyDownCount = keyDownCount
        self.leftMouseDownCount = leftMouseDownCount
        self.rightMouseDownCount = rightMouseDownCount
        self.otherMouseDownCount = otherMouseDownCount
        self.scrollWheelCount = scrollWheelCount
    }

    package static func current() -> Self {
        Self(
            keyDownCount: counter(for: .keyDown),
            leftMouseDownCount: counter(for: .leftMouseDown),
            rightMouseDownCount: counter(for: .rightMouseDown),
            otherMouseDownCount: counter(for: .otherMouseDown),
            scrollWheelCount: counter(for: .scrollWheel)
        )
    }

    private static func counter(for eventType: CGEventType) -> UInt32 {
        CGEventSource.counterForEventType(
            .combinedSessionState,
            eventType: eventType
        )
    }
}

package enum SelectionReplacementPolicy {
    package enum ReplacementAction: Equatable, Sendable {
        case pasteOverSelection
        case deleteBackward(characterCount: Int)
    }

    package static func replacementAction(
        applicationBundleIdentifier: String?,
        currentText: String,
        insertedText: String,
        insertedRange: NSRange
    ) -> ReplacementAction {
        let source = currentText as NSString
        guard applicationBundleIdentifier == "com.googlecode.iterm2",
              insertedRange.location >= 0,
              insertedRange.length > 0,
              NSMaxRange(insertedRange) <= source.length,
              source.substring(with: insertedRange)
                .replacingOccurrences(of: "\0", with: "") == insertedText else {
            return .pasteOverSelection
        }
        return .deleteBackward(characterCount: insertedText.count)
    }

    package static func preferredInsertedRange(
        selectionSnapshot: SelectionReplacementSnapshot?,
        textSnapshot: CorrectionObservationSnapshot?,
        currentText: String?,
        currentSelectedRange: NSRange?,
        interaction: ReplacementInteractionSnapshot = .current()
    ) -> NSRange? {
        if let selectionSnapshot,
           selectionSnapshot.canReplace(
            currentSelectedRange: currentSelectedRange,
            interaction: interaction
           ) {
            return selectionSnapshot.insertedRange
        }
        guard let textSnapshot,
              let currentText,
              textSnapshot.canReplaceInsertedText(in: currentText) else {
            return nil
        }
        return textSnapshot.insertedRange
    }

    package static func findInsertedRange(
        endingAt caretRange: NSRange,
        insertedText: String,
        selectedText: (NSRange) -> String?
    ) -> NSRange? {
        guard caretRange.location != NSNotFound,
              caretRange.location > 0,
              caretRange.length == 0,
              !insertedText.isEmpty else {
            return nil
        }
        let minimumLength = (insertedText as NSString).length
        let maximumLength = min(
            caretRange.location,
            max(minimumLength, insertedText.count * 4)
        )
        guard minimumLength <= maximumLength else { return nil }
        for length in minimumLength...maximumLength {
            let range = NSRange(
                location: caretRange.location - length,
                length: length
            )
            if selectedText(range)?
                .replacingOccurrences(of: "\0", with: "") == insertedText {
                return range
            }
        }
        return nil
    }
}

package struct SelectionReplacementSnapshot: Equatable, Sendable {
    package let caretRange: NSRange
    package let insertedRange: NSRange
    package let insertedText: String
    package let interaction: ReplacementInteractionSnapshot

    package init(
        caretRange: NSRange,
        insertedRange: NSRange,
        insertedText: String,
        interaction: ReplacementInteractionSnapshot
    ) {
        self.caretRange = caretRange
        self.insertedRange = insertedRange
        self.insertedText = insertedText
        self.interaction = interaction
    }

    package static func make(
        beforePasteRange: NSRange,
        afterPasteRange: NSRange,
        insertedText: String,
        interaction: ReplacementInteractionSnapshot = .current()
    ) -> Self? {
        guard beforePasteRange.location != NSNotFound,
              beforePasteRange.location >= 0,
              beforePasteRange.length == 0,
              afterPasteRange.location > beforePasteRange.location,
              afterPasteRange.length == 0 else {
            return nil
        }
        return Self(
            caretRange: afterPasteRange,
            insertedRange: NSRange(
                location: beforePasteRange.location,
                length: afterPasteRange.location - beforePasteRange.location
            ),
            insertedText: insertedText,
            interaction: interaction
        )
    }

    package func canReplace(
        currentSelectedRange: NSRange?,
        interaction currentInteraction: ReplacementInteractionSnapshot = .current()
    ) -> Bool {
        currentSelectedRange == caretRange
            && currentInteraction == interaction
    }

    package func matchesSelectedText(_ selectedText: String?) -> Bool {
        selectedText?.replacingOccurrences(of: "\0", with: "") == insertedText
    }
}

package struct CorrectionObservationSnapshot: Equatable, Sendable {
    package let originalText: String
    package let insertedRange: NSRange

    package init(originalText: String, insertedRange: NSRange) {
        self.originalText = originalText
        self.insertedRange = insertedRange
    }

    package static func make(
        originalText: String,
        insertionLocation: Int,
        insertedText: String
    ) -> Self? {
        make(
            originalText: originalText,
            selectedRange: NSRange(
                location: insertionLocation,
                length: 0
            ),
            insertedText: insertedText
        )
    }

    package static func make(
        originalText: String,
        selectedRange: NSRange,
        insertedText: String
    ) -> Self? {
        let source = originalText as NSString
        guard selectedRange.location != NSNotFound,
              selectedRange.location >= 0,
              selectedRange.length >= 0,
              NSMaxRange(selectedRange) <= source.length else {
            return nil
        }
        let updated = NSMutableString(string: originalText)
        updated.replaceCharacters(
            in: selectedRange,
            with: insertedText
        )
        return Self(
            originalText: updated as String,
            insertedRange: NSRange(
                location: selectedRange.location,
                length: (insertedText as NSString).length
            )
        )
    }

    package static func makeAfterPaste(
        currentText: String,
        caretLocation: Int,
        insertedText: String
    ) -> Self? {
        let current = currentText as NSString
        let insertedLength = (insertedText as NSString).length
        let insertionLocation = caretLocation - insertedLength
        guard insertedLength > 0,
              insertionLocation >= 0,
              caretLocation <= current.length else {
            return nil
        }
        let insertedRange = NSRange(
            location: insertionLocation,
            length: insertedLength
        )
        guard current.substring(with: insertedRange) == insertedText else {
            return nil
        }
        return Self(
            originalText: currentText,
            insertedRange: insertedRange
        )
    }

    package func canReplaceInsertedText(in currentText: String) -> Bool {
        let original = originalText as NSString
        let current = currentText as NSString
        let insertedEnd = NSMaxRange(insertedRange)
        guard insertedRange.location != NSNotFound,
              insertedRange.location >= 0,
              insertedRange.length > 0,
              insertedEnd <= original.length,
              insertedEnd <= current.length else {
            return false
        }
        let stablePrefix = NSRange(location: 0, length: insertedEnd)
        return current.substring(with: stablePrefix)
            == original.substring(with: stablePrefix)
    }
}
