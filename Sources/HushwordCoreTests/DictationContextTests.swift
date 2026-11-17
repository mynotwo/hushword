import HushwordCore
import Foundation

let dictationContextTests: [(String, () throws -> Void)] = [
    ("builds one dictation context from built-in and personal terms", {
        let context = DictationContext(
            personalDictionaryText: """
            长心存储 = 长鑫存储
            see ex em tee = CXMT
            invalid line
            """
        )
        guard context.dictionary == [
            "长心存储": "长鑫存储",
            "see ex em tee": "CXMT",
        ],
        context.recognitionTerms.contains("random signal"),
        context.recognitionTerms.contains("fine-tuning"),
        context.recognitionTerms.contains("长心存储"),
        context.recognitionTerms.contains("长鑫存储"),
        context.recognitionTerms.contains("see ex em tee"),
        context.recognitionTerms.contains("CXMT"),
        context.recognitionTerms == context.recognitionTerms.sorted() else {
            throw TestFailure(description: "dictation context lost built-in or personal terminology")
        }
    }),
    ("keeps manual dictionary ahead of correction memory", {
        let context = DictationContext(
            personalDictionaryText: "长心存储 = 长鑫存储",
            learnedCorrections: [
                LearnedCorrection(
                    observed: "长心存储",
                    preferred: "错误覆盖"
                ),
                LearnedCorrection(
                    observed: "Type less",
                    preferred: "Typeless"
                ),
            ]
        )
        guard context.dictionary["长心存储"] == "长鑫存储",
              context.dictionary["Type less"] == "Typeless",
              context.recognitionTerms.contains("Typeless") else {
            throw TestFailure(
                description: "Correction Memory overrode manual intent: \(context.dictionary)"
            )
        }
    }),
    ("includes frequent mixed-language product and evaluation terms", {
        let context = DictationContext(personalDictionaryText: "")
        let expectedTerms = [
            "ByteDance",
            "Hushword",
            "Typeless",
            "criteria",
            "meet criteria",
            "reward model",
        ]
        guard expectedTerms.allSatisfy(context.recognitionTerms.contains) else {
            throw TestFailure(
                description: "frequent mixed-language terms are missing: \(context.recognitionTerms)"
            )
        }
    }),
    ("derives terminology hints from repeated technical history", {
        let context = DictationContext(
            personalDictionaryText: "",
            historyTexts: [
                "我们继续测试 large-v3-turbo Q5 和 Qwen 2.5。",
                "large-v3-turbo Q5 的结果比 Qwen 2.5 稳定。",
                "Typeless 的断句更自然。",
                "我们再比较 Typeless 的体验。",
                "最后记录 Typeless 的差异。",
                "CXMT 的数据已经准备好了。",
                "明天继续分析 CXMT。",
            ]
        )
        guard context.terminologyHints.contains("large-v3-turbo Q5"),
              context.terminologyHints.contains("Qwen 2.5"),
              context.terminologyHints.contains("Typeless"),
              context.terminologyHints.contains("CXMT"),
              context.recognitionTerms.contains("large-v3-turbo Q5"),
              context.recognitionTerms.contains("Typeless") else {
            throw TestFailure(
                description: "repeated technical history did not produce hints: \(context.terminologyHints)"
            )
        }
    }),
    ("does not hint one-off or repeatedly duplicated mistakes", {
        let context = DictationContext(
            personalDictionaryText: "",
            historyTexts: [
                "Pocket Pocket Pocket。",
                "Pocket。",
                "Thank you。",
                "只提到一次 OneOffProduct。",
                "Qwen 2.5 Qwen 2.5 Qwen 2.5。",
            ]
        )
        guard context.terminologyHints.contains("Qwen 2.5") == false,
              context.terminologyHints.contains("Pocket") == false,
              context.terminologyHints.contains("Thank") == false,
              context.terminologyHints.contains("OneOffProduct") == false else {
            throw TestFailure(
                description: "untrusted vocabulary became a hint: \(context.terminologyHints)"
            )
        }
    }),
    ("keeps manual dictionary terms ahead of terminology hint limits", {
        let histories = (0..<40).flatMap { index in
            [
                "Model-\(index) appeared once.",
                "Model-\(index) appeared again.",
            ]
        }
        let context = DictationContext(
            personalDictionaryText: "see ex em tee = CXMT",
            historyTexts: histories
        )
        guard context.dictionary["see ex em tee"] == "CXMT",
              context.recognitionTerms.contains("see ex em tee"),
              context.recognitionTerms.contains("CXMT"),
              context.terminologyHints.count <= 30 else {
            throw TestFailure(
                description: "terminology hints displaced manual terms"
            )
        }
    }),
    ("learns one direct homophone correction inside the inserted text", {
        let original = "这么转的话，他早上可以不接单呀。"
        let edited = "这么赚的话，他早上可以不接单呀。"
        let correction = CorrectionMemoryPolicy.infer(
            originalText: original,
            editedText: edited,
            insertedRange: NSRange(
                location: 0,
                length: (original as NSString).length
            )
        )
        guard correction == LearnedCorrection(
            observed: "这么转的话",
            preferred: "这么赚的话"
        ) else {
            throw TestFailure(
                description: "direct user correction was not learned: \(String(describing: correction))"
            )
        }
    }),
    ("does not learn semantic rewrites or edits outside inserted text", {
        let semanticRewrite = CorrectionMemoryPolicy.infer(
            originalText: "这个方案可以。",
            editedText: "换一个完全不同的方案。",
            insertedRange: NSRange(location: 0, length: 7)
        )
        let outsideEdit = CorrectionMemoryPolicy.infer(
            originalText: "标题：这么转的话。",
            editedText: "新标题：这么转的话。",
            insertedRange: NSRange(location: 3, length: 7)
        )
        guard semanticRewrite == nil, outsideEdit == nil else {
            throw TestFailure(
                description: "Correction Memory learned an ambiguous edit"
            )
        }
    }),
    ("updates correction memory without overriding a manual entry", {
        let correction = LearnedCorrection(
            observed: "Type less",
            preferred: "Typeless"
        )
        let updated = CorrectionMemoryPolicy.updating(
            correction,
            in: [],
            manualDictionaryText: "长心存储 = 长鑫存储"
        )
        let preserved = CorrectionMemoryPolicy.updating(
            LearnedCorrection(
                observed: "长心存储",
                preferred: "错误覆盖"
            ),
            in: updated,
            manualDictionaryText: "长心存储 = 长鑫存储"
        )
        guard updated == [correction], preserved == updated else {
            throw TestFailure(
                description: "Correction Memory precedence regressed"
            )
        }
    }),
]
