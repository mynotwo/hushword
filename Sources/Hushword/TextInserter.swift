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
                let correctionObservation = CorrectionObservation.capture(
                    insertedText: text,
                    application: application
                )
                let didPaste = postPasteShortcut(
                    to: application.processIdentifier
                )
                let result: InsertionResult = didPaste
                    ? .pasted
                    : .copiedTargetUnavailable
                var completedObservation = correctionObservation
                if didPaste {
                    var completedSelection = completedObservation?
                        .completeSelectionSnapshotAfterPaste() ?? false
                    for _ in 0..<5 where !completedSelection {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        if let completedObservation {
                            completedSelection = completedObservation
                                .completeSelectionSnapshotAfterPaste()
                        } else {
                            completedObservation = CorrectionObservation
                                .captureAfterPaste(
                                    insertedText: text,
                                    application: application
                                )
                            completedSelection = completedObservation != nil
                        }
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

    func replace(
        _ text: String,
        using observation: CorrectionObservation?
    ) async -> InsertionAttempt {
        let clock = ContinuousClock()
        let startedAt = clock.now
        guard copy(text) else {
            return attempt(
                result: .copyFailed,
                activationDuration: .zero,
                totalDuration: startedAt.duration(to: clock.now)
            )
        }
        guard hasAccessibilityPermission else {
            return attempt(
                result: .copiedAccessibilityPermissionRequired,
                activationDuration: .zero,
                totalDuration: startedAt.duration(to: clock.now)
            )
        }
        guard let observation,
              observation.selectInsertedTextForReplacement() else {
            return attempt(
                result: .copiedTargetUnavailable,
                activationDuration: .zero,
                totalDuration: startedAt.duration(to: clock.now)
            )
        }
        if case .deleteBackward(let characterCount) =
            observation.replacementAction,
           !postDeleteBackward(
            count: characterCount,
            to: observation.targetProcessIdentifier
           ) {
            return attempt(
                result: .copiedTargetUnavailable,
                activationDuration: .zero,
                totalDuration: startedAt.duration(to: clock.now)
            )
        }
        guard
              postPasteShortcut(to: observation.targetProcessIdentifier) else {
            return attempt(
                result: .copiedTargetUnavailable,
                activationDuration: .zero,
                totalDuration: startedAt.duration(to: clock.now)
            )
        }
        return attempt(
            result: .pasted,
            activationDuration: .zero,
            totalDuration: startedAt.duration(to: clock.now)
        )
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

    private func postDeleteBackward(
        count: Int,
        to processIdentifier: pid_t
    ) -> Bool {
        guard count > 0,
              let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        for _ in 0..<count {
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 51,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 51,
                keyDown: false
            ) else {
                return false
            }
            keyDown.postToPid(processIdentifier)
            keyUp.postToPid(processIdentifier)
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

}
