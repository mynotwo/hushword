import AppKit
import ApplicationServices
import HushwordCore
import Foundation

/// The text of the focused field right after a paste, plus the UTF-16 range
/// Hushword inserted. Correction Memory compares later edits against it.
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
}

/// Watches the field Hushword just pasted into. If the user edits the
/// inserted range and the edit stays stable for two checks, the edit becomes
/// a candidate Correction Memory entry.
@MainActor
package final class CorrectionObservation {
    private let element: AXUIElement
    private let snapshot: CorrectionObservationSnapshot

    private init(
        element: AXUIElement,
        snapshot: CorrectionObservationSnapshot
    ) {
        self.element = element
        self.snapshot = snapshot
    }

    /// Captures the field before the paste and predicts its text afterwards.
    package static func capture(
        insertedText: String,
        application: NSRunningApplication
    ) -> CorrectionObservation? {
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let element = focusedElement(in: applicationElement),
              let selectedRange = selectedTextRange(of: element),
              let snapshot = stringValue(of: element).flatMap({
                  CorrectionObservationSnapshot.make(
                      originalText: $0,
                      selectedRange: selectedRange,
                      insertedText: insertedText
                  )
              }) else {
            return nil
        }
        return CorrectionObservation(element: element, snapshot: snapshot)
    }

    /// Captures the field after the paste, for apps whose pre-paste value
    /// was unavailable.
    package static func captureAfterPaste(
        insertedText: String,
        application: NSRunningApplication
    ) -> CorrectionObservation? {
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let element = focusedElement(in: applicationElement),
              let currentText = stringValue(of: element),
              let selectedRange = selectedTextRange(of: element),
              selectedRange.length == 0,
              let snapshot = CorrectionObservationSnapshot.makeAfterPaste(
                  currentText: currentText,
                  caretLocation: selectedRange.location,
                  insertedText: insertedText
              ) else {
            return nil
        }
        return CorrectionObservation(element: element, snapshot: snapshot)
    }

    package func waitForCorrection(
        maximumChecks: Int = 30,
        intervalNanoseconds: UInt64 = 500_000_000
    ) async -> LearnedCorrection? {
        var stableCorrection: LearnedCorrection?
        for _ in 0..<max(0, maximumChecks) {
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
            guard !Task.isCancelled,
                  let editedText = Self.stringValue(of: element) else {
                return nil
            }
            guard editedText != snapshot.originalText else {
                stableCorrection = nil
                continue
            }
            let correction = CorrectionMemoryPolicy.infer(
                originalText: snapshot.originalText,
                editedText: editedText,
                insertedRange: snapshot.insertedRange
            )
            if correction == stableCorrection {
                return correction
            }
            stableCorrection = correction
        }
        return nil
    }

    private static func focusedElement(
        in applicationElement: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringValue(
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func selectedTextRange(
        of element: AXUIElement
    ) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(
            unsafeBitCast(value, to: AXValue.self),
            .cfRange,
            &range
        ) else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }
}
