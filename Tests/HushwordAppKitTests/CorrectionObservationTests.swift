import HushwordCore
import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    static func replacesOnlyUnchangedLastInsertion() async throws {
        let snapshot = CorrectionObservationSnapshot(
            originalText: "开头本地听写结尾",
            insertedRange: NSRange(location: 2, length: 4)
        )

        guard snapshot.canReplaceInsertedText(in: "开头本地听写结尾"),
              snapshot.canReplaceInsertedText(in: "开头本地听写结尾，新增"),
              snapshot.canReplaceInsertedText(in: "开头已经修改结尾") == false else {
            throw TestFailure(
                description: "Agent rewrite can overwrite text changed after dictation"
            )
        }
    }

    static func selectsPastedRangeOnlyWhileItsCaretStaysUnchanged() async throws {
        let interaction = ReplacementInteractionSnapshot(
            keyDownCount: 10,
            leftMouseDownCount: 20,
            rightMouseDownCount: 30,
            otherMouseDownCount: 40,
            scrollWheelCount: 50
        )
        let snapshot = SelectionReplacementSnapshot.make(
            beforePasteRange: NSRange(location: 4, length: 0),
            afterPasteRange: NSRange(location: 20, length: 0),
            insertedText: "Hi 👋，世界",
            interaction: interaction
        )

        guard snapshot?.insertedRange == NSRange(location: 4, length: 16),
              snapshot?.matchesSelectedText("H\u{0}i\u{0} 👋，世界\u{0}") == true,
              snapshot?.matchesSelectedText("Hi 👋，世") == false,
              snapshot?.canReplace(
                currentSelectedRange: NSRange(location: 20, length: 0),
                interaction: interaction
              ) == true,
              snapshot?.canReplace(
                currentSelectedRange: NSRange(location: 19, length: 0),
                interaction: interaction
              ) == false,
              snapshot?.canReplace(
                currentSelectedRange: NSRange(location: 20, length: 0),
                interaction: ReplacementInteractionSnapshot(
                    keyDownCount: 11,
                    leftMouseDownCount: 20,
                    rightMouseDownCount: 30,
                    otherMouseDownCount: 40,
                    scrollWheelCount: 50
                )
              ) == false else {
            throw TestFailure(
                description: "range replacement can select stale or edited input"
            )
        }
    }

    static func findsExactITermPastedRangeThroughNULSeparators() async throws {
        let insertedText = "Hushword覆盖测试原文"
        let prefix = "/model"
        let rawInsertedText = insertedText.map { "\($0)\u{0}" }.joined()
        let rawText = (prefix + rawInsertedText) as NSString
        let caretRange = NSRange(location: rawText.length, length: 0)
        let expectedRange = NSRange(
            location: (prefix as NSString).length,
            length: (rawInsertedText as NSString).length
        )

        let foundRange = SelectionReplacementPolicy.findInsertedRange(
            endingAt: caretRange,
            insertedText: insertedText,
            selectedText: { range in
                guard NSMaxRange(range) <= rawText.length else { return nil }
                return rawText.substring(with: range)
            }
        )

        guard foundRange == expectedRange else {
            throw TestFailure(
                description: "iTerm pasted range was guessed from the prompt instead of matched text"
            )
        }
    }

    static func prefersExactSelectionOverTerminalTextSnapshot() async throws {
        let interaction = ReplacementInteractionSnapshot(
            keyDownCount: 10,
            leftMouseDownCount: 20,
            rightMouseDownCount: 30,
            otherMouseDownCount: 40,
            scrollWheelCount: 50
        )
        let exactSelection = SelectionReplacementSnapshot(
            caretRange: NSRange(location: 20, length: 0),
            insertedRange: NSRange(location: 6, length: 14),
            insertedText: "Hushword覆盖测试原文",
            interaction: interaction
        )
        let terminalTextSnapshot = CorrectionObservationSnapshot(
            originalText: "/modelHushword覆盖测试原文",
            insertedRange: NSRange(location: 0, length: 20)
        )

        let range = SelectionReplacementPolicy.preferredInsertedRange(
            selectionSnapshot: exactSelection,
            textSnapshot: terminalTextSnapshot,
            currentText: "/modelHushword覆盖测试原文",
            currentSelectedRange: NSRange(location: 20, length: 0),
            interaction: interaction
        )

        guard range == exactSelection.insertedRange else {
            throw TestFailure(
                description: "terminal replacement preferred an unverified prompt range"
            )
        }
    }

    static func usesVerifiedBackwardDeletionForTerminalInput() async throws {
        guard SelectionReplacementPolicy.replacementAction(
            applicationBundleIdentifier: "com.googlecode.iterm2",
            currentText: "提示符\0Hushword\0覆盖\0测试\0原文\0",
            insertedText: "Hushword覆盖测试原文",
            insertedRange: NSRange(location: 4, length: 18)
        ) == .deleteBackward(characterCount: 14),
        SelectionReplacementPolicy.replacementAction(
            applicationBundleIdentifier: "com.apple.TextEdit",
            currentText: "前缀Hushword覆盖测试原文",
            insertedText: "Hushword覆盖测试原文",
            insertedRange: NSRange(location: 2, length: 14)
        ) == .pasteOverSelection else {
            throw TestFailure(
                description: "terminal replacement still relies on an ignored AX selection"
            )
        }
    }

    @MainActor
    static func capturesExactUTF16InsertedTextRange() async throws {
        let snapshot = CorrectionObservationSnapshot.make(
            originalText: "标题：",
            insertionLocation: 3,
            insertedText: "这么转的话。"
        )
        guard snapshot == CorrectionObservationSnapshot(
            originalText: "标题：这么转的话。",
            insertedRange: NSRange(location: 3, length: 6)
        ) else {
            throw TestFailure(
                description: "correction observation lost the exact inserted range"
            )
        }
    }

    static func recoversInsertedRangeAfterPaste() async throws {
        let snapshot = CorrectionObservationSnapshot.makeAfterPaste(
            currentText: "标题：这么转的话。结尾",
            caretLocation: 9,
            insertedText: "这么转的话。"
        )
        guard snapshot == CorrectionObservationSnapshot(
            originalText: "标题：这么转的话。结尾",
            insertedRange: NSRange(location: 3, length: 6)
        ),
        CorrectionObservationSnapshot.makeAfterPaste(
            currentText: "标题：已经不同。结尾",
            caretLocation: 9,
            insertedText: "这么转的话。"
        ) == nil else {
            throw TestFailure(
                description: "post-paste capture trusted the wrong text range"
            )
        }
    }

    @MainActor
    static func persistsLearnedCorrectionsLocally() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-correction-store-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppStore(directory: directory)
        let corrections = [
            LearnedCorrection(
                observed: "这么转的话",
                preferred: "这么赚的话"
            ),
            LearnedCorrection(
                observed: "Type less",
                preferred: "Typeless"
            ),
        ]
        store.saveLearnedCorrections(corrections)

        guard AppStore(directory: directory).loadLearnedCorrections()
            == corrections else {
            throw TestFailure(
                description: "learned corrections did not survive a local reload"
            )
        }
    }
}
