import AppKit
import ApplicationServices
import HushwordCore

package struct TextInsertionMetrics: Equatable, Sendable {
    package let activationMilliseconds: Int64
    package let totalMilliseconds: Int64

    package init(
        activationMilliseconds: Int64,
        totalMilliseconds: Int64
    ) {
        self.activationMilliseconds = max(0, activationMilliseconds)
        self.totalMilliseconds = max(0, totalMilliseconds)
    }
}

@MainActor
struct TextInserter {
    enum InsertionResult {
        case pasted
        case copiedAccessibilityPermissionRequired
        case copiedTargetUnavailable
        case copyFailed
    }

    struct InsertionAttempt {
        let result: InsertionResult
        let metrics: TextInsertionMetrics
        let correctionObservation: CorrectionObservation?
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func insert(
        _ text: String,
        into application: NSRunningApplication?
    ) async -> InsertionAttempt {
        let clock = ContinuousClock()
        let insertionStartedAt = clock.now

        guard copy(text) else {
            return attempt(
                result: .copyFailed,
                activationDuration: .zero,
                totalDuration: insertionStartedAt.duration(to: clock.now)
            )
        }
        guard let application, !application.isTerminated else {
            return attempt(
                result: .copiedTargetUnavailable,
                activationDuration: .zero,
                totalDuration: insertionStartedAt.duration(to: clock.now)
            )
        }
        guard hasAccessibilityPermission else {
            return attempt(
                result: .copiedAccessibilityPermissionRequired,
                activationDuration: .zero,
                totalDuration: insertionStartedAt.duration(to: clock.now)
            )
        }

        let activationStartedAt = clock.now
        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        var activationState = PasteActivationState(maximumChecks: 20)
        while true {
            let isActive = application.isActive
                || NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == application.processIdentifier
            switch activationState.next(targetIsActive: isActive) {
            case .retry:
                try? await Task.sleep(nanoseconds: 50_000_000)
            case .paste:
                let activationDuration = activationStartedAt.duration(to: clock.now)
                let prePasteObservation = CorrectionObservation.capture(
                    insertedText: text,
                    application: application
                )
                let didPaste = postPasteShortcut(
                    to: application.processIdentifier
                )
                let result: InsertionResult = didPaste
                    ? .pasted
                    : .copiedTargetUnavailable
                var completedObservation = prePasteObservation
                if didPaste, completedObservation == nil {
                    for _ in 0..<5 where completedObservation == nil {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        completedObservation = CorrectionObservation
                            .captureAfterPaste(
                                insertedText: text,
                                application: application
                            )
                    }
                }
                return attempt(
                    result: result,
                    activationDuration: activationDuration,
                    totalDuration: insertionStartedAt.duration(to: clock.now),
                    correctionObservation: didPaste
                        ? completedObservation
                        : nil
                )
            case .giveUp:
                return attempt(
                    result: .copiedTargetUnavailable,
                    activationDuration: activationStartedAt.duration(to: clock.now),
                    totalDuration: insertionStartedAt.duration(to: clock.now)
                )
            }
        }
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func attempt(
        result: InsertionResult,
        activationDuration: Duration,
        totalDuration: Duration,
        correctionObservation: CorrectionObservation? = nil
    ) -> InsertionAttempt {
        InsertionAttempt(
            result: result,
            metrics: TextInsertionMetrics(
                activationMilliseconds: milliseconds(activationDuration),
                totalMilliseconds: milliseconds(totalDuration)
            ),
            correctionObservation: correctionObservation
        )
    }

    private func milliseconds(_ duration: Duration) -> Int64 {
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

    private func postPasteShortcut(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
              ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

}
