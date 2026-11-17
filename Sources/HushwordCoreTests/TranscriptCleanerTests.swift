import HushwordCore

let transcriptCleanerTests: [(String, () throws -> Void)] = [
    ("removes English filler words and repetitions", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("Um I I think we should should ship this today"),
            "I think we should ship this today.",
            "removes English filler words and repetitions"
        )
    }),
    ("converts spoken punctuation and list commands", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("今天有三件事 冒号 新的一行 第一 更新模型 新的一行 第二 修复登录 句号"),
            "今天有三件事：\n第一，更新模型\n第二，修复登录。",
            "converts spoken punctuation and list commands"
        )
    }),
    ("keeps final phrase after self correction", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("Let's meet on Tuesday no actually Wednesday at three"),
            "Let's meet on Wednesday at three.",
            "keeps final phrase after self correction"
        )
    }),
    ("applies personal dictionary", {
        let cleaner = TranscriptCleaner(dictionary: ["长心存储": "长鑫存储", "see ex em tee": "CXMT"])
        try expectEqual(
            cleaner.clean("长心存储 also called see ex em tee"),
            "长鑫存储 also called CXMT.",
            "applies personal dictionary"
        )
    }),
    ("preserves terminal punctuation", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("Are we ready question mark"),
            "Are we ready?",
            "preserves terminal punctuation"
        )
    }),
    ("removes leading Chinese hesitation without removing the opinion", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("哎呀，嗯，我我觉得这个方案可以"),
            "我觉得这个方案可以。",
            "removes leading Chinese hesitation without removing the opinion"
        )
    }),
    ("preserves an expressive Chinese interjection", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("哎呀这个蛋糕真好吃"),
            "哎呀这个蛋糕真好吃。",
            "preserves an expressive Chinese interjection"
        )
    }),
    ("collapses only repeated discourse words and preserves technical terms", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean(
                "这个这个方案先回测，然后然后再发布，Typeless、Qwen 2.5 和 large-v3-turbo Q5 都保留"
            ),
            "这个方案先回测，然后再发布，Typeless、Qwen 2.5 和 large-v3-turbo Q5 都保留。",
            "collapses only repeated discourse words and preserves technical terms"
        )
    }),
    ("normalizes Whisper ASCII commas in Chinese mixed-language text", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean(
                "这个方案先回测,然后再发布, Typeless, Qwen, large-v3-turbo Q5都保留"
            ),
            "这个方案先回测，然后再发布，Typeless, Qwen, large-v3-turbo Q5都保留。",
            "normalizes Whisper ASCII commas in Chinese mixed-language text"
        )
    }),
    ("normalizes prompted Whisper separators without losing terminology", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean(
                "我们已经做了很多实验＞使用 random signal＞所以我们能发 paper 吗＞现在继续＞"
            ),
            "我们已经做了很多实验，使用 random signal，所以我们能发 paper 吗？现在继续。",
            "normalizes prompted Whisper separators without losing terminology"
        )
    }),
    ("formats an explicit three-step spoken list", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean(
                "我们做三件事第一检查模型第二跑回测最后打包发布"
            ),
            "我们做三件事：\n第一，检查模型；\n第二，跑回测；\n最后，打包发布。",
            "formats an explicit three-step spoken list"
        )
    }),
    ("formats a Whisper list that uses ASCII commas", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean(
                "我们做三件事,第一检查模型,第二跑回侧,最后到包发布"
            ),
            "我们做三件事：\n第一，检查模型；\n第二，跑回侧；\n最后，到包发布。",
            "formats a Whisper list that uses ASCII commas"
        )
    }),
    ("preserves meaningful negation and hedging", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("我觉得这个结论不对，所以不能发布"),
            "我觉得这个结论不对，所以不能发布。",
            "preserves meaningful negation and hedging"
        )
    }),
    ("does not mistake unpunctuated negation for self correction", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("这个结论不对所以不能发布"),
            "这个结论不对所以不能发布。",
            "does not mistake unpunctuated negation for self correction"
        )
    }),
    ("keeps an explicit Chinese self correction", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("我们周二开会不对周三开会"),
            "我们周三开会。",
            "keeps an explicit Chinese self correction"
        )
    }),
    ("does not format ordinary ordinal references as a list", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean("第一版和第二版都保留"),
            "第一版和第二版都保留。",
            "does not format ordinary ordinal references as a list"
        )
    }),
    ("preserves numbers and model names during semantic cleanup", {
        let cleaner = TranscriptCleaner()
        try expectEqual(
            cleaner.clean(
                "这个这个方案使用Qwen 2.5和large-v3-turbo Q5准确率82%"
            ),
            "这个方案使用Qwen 2.5和large-v3-turbo Q5准确率82%.",
            "preserves numbers and model names during semantic cleanup"
        )
    }),
    ("keeps conservative semantic organization idempotent", {
        let cleaner = TranscriptCleaner()
        let once = cleaner.clean(
            "哎呀，我们做三件事第一检查模型第二跑回测最后打包发布"
        )
        try expectEqual(
            cleaner.clean(once),
            once,
            "keeps conservative semantic organization idempotent"
        )
    }),
    ("passes a synthetic short medium and long semantic cleanup suite", {
        let cleaner = TranscriptCleaner()
        let fixtures = [
            ("嗯，我们明天发布", "我们明天发布。"),
            ("呃 先跑回测", "先跑回测。"),
            ("哎呀太好了", "哎呀太好了。"),
            ("我我觉得这个可以", "我觉得这个可以。"),
            ("然后然后再检查日志", "然后再检查日志。"),
            ("这个这个版本使用Qwen 2.5", "这个版本使用Qwen 2.5."),
            ("第一版和第二版都保留", "第一版和第二版都保留。"),
            ("这个结论不对所以不能发布", "这个结论不对所以不能发布。"),
            ("我们周二开会不对周三开会", "我们周三开会。"),
            (
                "我们做三件事第一检查模型第二跑回测最后打包发布",
                "我们做三件事：\n第一，检查模型；\n第二，跑回测；\n最后，打包发布。"
            ),
            (
                "这个这个方案保留large-v3-turbo Q5准确率82%",
                "这个方案保留large-v3-turbo Q5准确率82%."
            ),
            (
                "其实其实我们先检查模型然后然后跑回测最后再发布",
                "其实我们先检查模型然后跑回测最后再发布。"
            ),
        ]
        for (input, expected) in fixtures {
            try expectEqual(
                cleaner.clean(input),
                expected,
                "synthetic semantic cleanup fixture: \(input)"
            )
        }
    }),
]
