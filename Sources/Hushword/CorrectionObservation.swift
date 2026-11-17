import AppKit
import ApplicationServices
import HushwordCore
import Foundation

@MainActor
package final class CorrectionObservation {
    private let element: AXUIElement
    private let processIdentifier: pid_t
    private let insertedText: String
    private let snapshot: CorrectionObservationSnapshot?
    private let beforePasteRange: NSRange?
    private let interaction: ReplacementInteractionSnapshot?
    private var selectionSnapshot: SelectionReplacementSnapshot?
    package var targetProcessIdentifier: pid_t {
        processIdentifier
    }
    package private(set) var replacementAction =
        SelectionReplacementPolicy.ReplacementAction.pasteOverSelection

    private init(
        element: AXUIElement,
        processIdentifier: pid_t,
        insertedText: String,
        snapshot: CorrectionObservationSnapshot?,
        beforePasteRange: NSRange?,
        interaction: ReplacementInteractionSnapshot?,
        selectionSnapshot: SelectionReplacementSnapshot?
    ) {
        self.element = element
        self.processIdentifier = processIdentifier
        self.insertedText = insertedText
        self.snapshot = snapshot
        self.beforePasteRange = beforePasteRange
        self.interaction = interaction
        self.selectionSnapshot = selectionSnapshot
    }

    package static func capture(
        insertedText: String,
        application: NSRunningApplication
    ) -> CorrectionObservation? {
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let element = focusedElement(in: applicationElement),
              let selectedRange = selectedTextRange(of: element) else {
            return nil
        }
        let snapshot = stringValue(of: element).flatMap {
            CorrectionObservationSnapshot.make(
                originalText: $0,
                selectedRange: selectedRange,
                insertedText: insertedText
            )
        }
        let canObserveSelection = selectedRange.length == 0
        guard snapshot != nil || canObserveSelection else { return nil }
        return CorrectionObservation(
            element: element,
            processIdentifier: application.processIdentifier,
            insertedText: insertedText,
            snapshot: snapshot,
            beforePasteRange: canObserveSelection ? selectedRange : nil,
            interaction: canObserveSelection ? .current() : nil,
            selectionSnapshot: nil
        )
    }

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
        return CorrectionObservation(
            element: element,
            processIdentifier: application.processIdentifier,
            insertedText: insertedText,
            snapshot: snapshot,
            beforePasteRange: nil,
            interaction: nil,
            selectionSnapshot: nil
        )
    }

    package func completeSelectionSnapshotAfterPaste() -> Bool {
        if selectionSnapshot != nil {
            return true
        }
        guard let beforePasteRange,
              let interaction,
              let afterPasteRange = Self.selectedTextRange(of: element),
              let currentText = Self.stringValue(of: element) else {
            return false
        }
        let source = currentText as NSString
        let candidateRange = NSRange(
            location: beforePasteRange.location,
            length: afterPasteRange.location - beforePasteRange.location
        )
        let insertedRange: NSRange?
        if candidateRange.location >= 0,
           candidateRange.length > 0,
           NSMaxRange(candidateRange) <= source.length,
           SelectionReplacementSnapshot(
                caretRange: afterPasteRange,
                insertedRange: candidateRange,
                insertedText: insertedText,
                interaction: interaction
           ).matchesSelectedText(source.substring(with: candidateRange)) {
            insertedRange = candidateRange
        } else {
            insertedRange = SelectionReplacementPolicy.findInsertedRange(
                endingAt: afterPasteRange,
                insertedText: insertedText,
                selectedText: { range in
                    guard NSMaxRange(range) <= source.length else {
                        return nil
                    }
                    return source.substring(with: range)
                }
            )
        }
        guard let insertedRange else {
            return false
        }
        selectionSnapshot = SelectionReplacementSnapshot(
            caretRange: afterPasteRange,
            insertedRange: insertedRange,
            insertedText: insertedText,
            interaction: interaction
        )
        return true
    }

    package func waitForCorrection(
        maximumChecks: Int = 30,
        intervalNanoseconds: UInt64 = 500_000_000
    ) async -> LearnedCorrection? {
        guard let snapshot else { return nil }
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

    package func selectInsertedTextForReplacement() -> Bool {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == processIdentifier,
              let focusedElement = Self.focusedElement(in: applicationElement),
              CFEqual(focusedElement, element) else {
            return false
        }
        let currentSelectedRange = Self.selectedTextRange(of: element)
        let currentText = Self.stringValue(of: element)
        guard let insertedRange = SelectionReplacementPolicy
            .preferredInsertedRange(
                selectionSnapshot: selectionSnapshot,
                textSnapshot: snapshot,
                currentText: currentText,
                currentSelectedRange: currentSelectedRange
            ) else {
            return false
        }
        if let currentText {
            replacementAction = SelectionReplacementPolicy.replacementAction(
                applicationBundleIdentifier: NSRunningApplication(
                    processIdentifier: processIdentifier
                )?.bundleIdentifier,
                currentText: currentText,
                insertedText: insertedText,
                insertedRange: insertedRange
            )
        }
        let expectedSelection = selectionSnapshot?.insertedRange == insertedRange
            ? selectionSnapshot
            : nil
        guard Self.setSelectedTextRange(insertedRange, on: element) else {
            return false
        }
        guard let expectedSelection else { return true }
        guard expectedSelection.matchesSelectedText(
            Self.selectedText(of: element)
        ) else {
            _ = Self.setSelectedTextRange(
                expectedSelection.caretRange,
                on: element
            )
            return false
        }
        if case .deleteBackward = replacementAction {
            return Self.setSelectedTextRange(
                expectedSelection.caretRange,
                on: element
            )
        }
        return true
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

    private static func selectedText(
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func setSelectedTextRange(
        _ selectedRange: NSRange,
        on element: AXUIElement
    ) -> Bool {
        var range = CFRange(
            location: selectedRange.location,
            length: selectedRange.length
        )
        guard let value = AXValueCreate(.cfRange, &range) else {
            return false
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
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
