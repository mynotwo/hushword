import XCTest
@testable import HushwordCore

final class TranscriptCleanerTests: XCTestCase {
    func testRemovesEnglishFillersAndRepetitions() {
        let cleaner = TranscriptCleaner()
        let output = cleaner.clean("Um I I think we should should ship this today")
        XCTAssertEqual(output, "I think we should ship this today.")
    }

    func testConvertsSpokenPunctuationAndListCommands() {
        let cleaner = TranscriptCleaner()
        let output = cleaner.clean("今天有三件事 冒号 新的一行 第一 更新模型 新的一行 第二 修复登录 句号")
        XCTAssertEqual(output, "今天有三件事：\n第一，更新模型\n第二，修复登录。")
    }

    func testKeepsFinalPhraseAfterSelfCorrection() {
        let cleaner = TranscriptCleaner()
        let output = cleaner.clean("Let's meet on Tuesday no actually Wednesday at three")
        XCTAssertEqual(output, "Let's meet on Wednesday at three.")
    }

    func testAppliesPersonalDictionary() {
        let cleaner = TranscriptCleaner(dictionary: ["长心存储": "长鑫存储", "see ex em tee": "CXMT"])
        let output = cleaner.clean("长心存储 also called see ex em tee")
        XCTAssertEqual(output, "长鑫存储 also called CXMT.")
    }

    func testPreservesTerminalPunctuation() {
        let cleaner = TranscriptCleaner()
        let output = cleaner.clean("Are we ready question mark")
        XCTAssertEqual(output, "Are we ready?")
    }
}
