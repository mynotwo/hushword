import Darwin
import HushwordCore
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual(_ actual: String, _ expected: String, _ name: String) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(name)\nexpected: \(expected.debugDescription)\nactual:   \(actual.debugDescription)")
    }
}

let tests: [(String, () throws -> Void)] = [
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
    ("builds a constrained concise polish prompt", {
        let prompt = AIPolishPrompt.build(
            text: "嗯这个事情我们明天再说",
            mode: .concise
        )
        guard prompt.contains("不得添加原文没有的事实"),
              prompt.contains("只输出润色后的正文"),
              prompt.contains("简洁") else {
            throw TestFailure(description: "prompt is missing safety or mode instructions: \(prompt)")
        }
    }),
    ("sanitizes fenced AI output", {
        try expectEqual(
            AIOutputSanitizer.sanitize("```text\n润色后的正文。\n```"),
            "润色后的正文。",
            "sanitizes fenced AI output"
        )
    }),
    ("sanitizes explanatory AI prefix", {
        try expectEqual(
            AIOutputSanitizer.sanitize("润色结果：\n这件事明天下午再讨论。"),
            "这件事明天下午再讨论。",
            "sanitizes explanatory AI prefix"
        )
    }),
    ("borrows safe Apple punctuation without replacing Whisper terminology", {
        let cleaner = TranscriptCleaner()
        let whisper = cleaner.clean(
            "我们已经做了很多实验RL不是交给模型新的能力使用 random signal在 fine-tuning 的情况下也可以达到类似结果所以我们能发 paper 吗?现在只是说这个定义是怎么回事"
        )
        let apple = cleaner.clean(
            "我们已经做了很多实验，RL 不是交给模型新的能力。使用 random sick know，在 fine to ling 的情况下也可以达到类似结果。所以我们能发 PK 吗？现在只是说，这个定义是怎么回事？"
        )
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: apple,
            contextualStrings: ["RL", "random signal", "fine-tuning", "paper"]
        )
        try expectEqual(
            cleaner.clean(selected),
            "我们已经做了很多实验，RL不是交给模型新的能力。使用 random signal，在 fine-tuning 的情况下也可以达到类似结果。所以我们能发 paper 吗？现在只是说，这个定义是怎么回事？",
            "borrows safe Apple punctuation without replacing Whisper terminology"
        )
    }),
    ("borrows better Apple sentence boundaries when punctuation counts match", {
        let whisper = "我感觉现在要卖出去，还有一个要优化的就是断句我觉得我们现在的断句做得还是不如Typeless。"
        let apple = "我感觉现在要卖出去还有一个要优化的就是断句。我觉得我们现在的断句做得还是不如Type less。"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: apple,
            contextualStrings: ["Typeless"]
        )
        try expectEqual(
            selected,
            "我感觉现在要卖出去，还有一个要优化的就是断句。我觉得我们现在的断句做得还是不如Typeless。",
            "borrows better Apple sentence boundaries when punctuation counts match"
        )
    }),
    ("segments a long request without changing its words", {
        let whisper = "要不你偷偷看看所有那里有什么东西吧你替他删一下算了但是他好久不用了他的东西然后那个保留策略你改一下不要让他老是满。"
        let apple = "要不你偷偷看看所有那里有什么东西吧。你替他删一下算了，但是他好久不用了他的东西。然后那个保留策略你改一下，不要让他老是满。"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: apple,
            contextualStrings: []
        )
        try expectEqual(
            selected,
            apple,
            "segments a long request without changing its words"
        )
    }),
    ("segments a long mixed-language thought without rewriting it", {
        let whisper = "好棒呀接下来我们该怎么用它开始赚钱呀我想手机版的是不是可以慢点上因为手机上有Apple本身的那个其实就还挺好用的我不知道耶你说呢？"
        let apple = "好棒呀，接下来我们该怎么用它开始赚钱呀？我想手机版的是不是可以慢点上？因为手机上有Apple本身的那个其实就还挺好用的，我不知道耶，你说呢？"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: apple,
            contextualStrings: ["Apple"]
        )
        try expectEqual(
            selected,
            apple,
            "segments a long mixed-language thought without rewriting it"
        )
    }),
    ("does not transfer punctuation across unrelated candidates", {
        let whisper = "Qwen 的量化模型会保留在本地运行"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: "今天天气很好，我们出去散步吧。",
            contextualStrings: ["Qwen"]
        )
        try expectEqual(
            selected,
            whisper,
            "does not transfer punctuation across unrelated candidates"
        )
    }),
    ("keeps complete Whisper text when the Apple candidate is truncated", {
        let cleaner = TranscriptCleaner()
        let whisper = cleaner.clean(
            "我们已经检查了 Qwen 的配置现在继续测试输出是否正确"
        )
        let apple = cleaner.clean(
            "我们已经检查了 Question 的配置，现在继续测试"
        )
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: apple,
            contextualStrings: ["Qwen"]
        )
        try expectEqual(
            selected,
            whisper,
            "keeps complete Whisper text when the Apple candidate is truncated"
        )
    }),
    ("does not place a truncated Apple full stop inside Whisper text", {
        let cleaner = TranscriptCleaner()
        let whisper = cleaner.clean(
            "我们已经检查了 Qwen 的配置现在继续测试输出是否正确最后保存结果"
        )
        let apple = cleaner.clean(
            "我们已经检查了 Qwen 的配置，现在继续测试输出是否正确"
        )
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: apple,
            contextualStrings: ["Qwen"]
        )
        try expectEqual(
            selected,
            "我们已经检查了 Qwen 的配置，现在继续测试输出是否正确最后保存结果。",
            "does not place a truncated Apple full stop inside Whisper text"
        )
    }),
    ("prefers the complete Apple candidate for short Chinese disagreements", {
        let apple = "昨晚的识别度最好。"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: "昨晚的识别都。",
            appleTranscript: apple,
            contextualStrings: []
        )
        guard selected == apple else {
            throw TestFailure(description: "short Chinese did not prefer Apple: \(selected)")
        }
    }),
    ("prefers the complete whole-recording candidate when Apple drops a sentence", {
        let whisper = "先介绍方法和架构，然后解释为什么需要购买这些数据，最后给出价格和替代方案。"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: whisper,
            appleTranscript: "先介绍方法和架构，然后解释为什么需要购买这些数据。",
            contextualStrings: []
        )
        guard selected == whisper else {
            throw TestFailure(
                description: "a truncated Apple candidate replaced the complete recording: \(selected)"
            )
        }
    }),
    ("builds a tool-free Claude command", {
        let command = AICommandBuilder.build(
            provider: .claude,
            prompt: "polish me",
            homeDirectory: "/Users/test",
            outputFile: "/tmp/output.txt"
        )
        guard command.executable == "/Users/test/.local/bin/claude",
              command.arguments.contains("--safe-mode"),
              command.arguments.contains("--no-session-persistence"),
              command.arguments.contains("--disable-slash-commands"),
              command.arguments.contains("--tools"),
              command.arguments.contains("") else {
            throw TestFailure(description: "unsafe Claude command: \(command)")
        }
    }),
    ("builds a persistent Codex app-server command", {
        let command = AICommandBuilder.buildCodexSession(
            homeDirectory: "/Users/test"
        )
        guard command.executable == "/Users/test/.local/bin/codex",
              command.arguments == ["app-server", "--stdio"],
              !command.arguments.contains("exec") else {
            throw TestFailure(
                description: "Codex rewrite does not use app-server: \(command)"
            )
        }
    }),
    ("finds a Hermes-installed Codex executable", {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-codex-location-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".hermes/node/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let command = AICommandBuilder.buildCodexSession(
            homeDirectory: directory.path
        )
        guard command.executable == executableURL.path else {
            throw TestFailure(
                description: "Hermes Codex was not discovered: \(command)"
            )
        }
    }),
    ("builds a read-only ephemeral Coco command", {
        let command = AICommandBuilder.build(
            provider: .coco,
            prompt: "polish me",
            homeDirectory: "/Users/test",
            outputFile: "/tmp/output.txt"
        )
        guard command.executable == "/Users/test/.local/bin/coco",
              command.arguments.contains("--ignore-user-config"),
              command.arguments.contains("--ephemeral"),
              command.arguments.contains("read-only"),
              command.arguments.contains("/tmp/output.txt") else {
            throw TestFailure(description: "unsafe Coco command: \(command)")
        }
    }),
    ("uses a short Fn press for dictation", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress,
        state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .shortPress else {
            throw TestFailure(description: "short Fn press did not toggle dictation")
        }
    }),
    ("uses a long Fn press only for Agent rewrite", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress,
        state.consumeLongPress() == .longPress,
        state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .none else {
            throw TestFailure(description: "long Fn press also toggled dictation")
        }
    }),
    ("falls back to a short Fn press when long press is unavailable", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress,
        state.consumeLongPress() == .longPress else {
            throw TestFailure(description: "Fn long press was not recognized")
        }
        state.cancelLongPress()
        guard state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .shortPress else {
            throw TestFailure(
                description: "unavailable Fn long press swallowed dictation"
            )
        }
    }),
    ("recovers Fn after its event stream is interrupted", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress else {
            throw TestFailure(description: "initial Fn press was lost")
        }
        state.reset()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress else {
            throw TestFailure(
                description: "Fn remained stuck after event tap recovery"
            )
        }
    }),
    ("ignores Fn modifier combinations", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: true
        ) == .none,
        state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .none else {
            throw TestFailure(description: "Fn combination incorrectly toggled dictation")
        }
    }),
    ("keeps the recording presentation out of a popover", {
        guard RecordingPresentationPolicy.shouldShowPopover(isRecording: true) == false,
              RecordingPresentationPolicy.shouldShowPopover(isRecording: false) else {
            throw TestFailure(description: "recording presentation left a popover visible")
        }
    }),
    ("maps dictation lifecycle to a continuous compact HUD", {
        guard RecordingPresentationPolicy.hudPhase(for: .idle) == .hidden,
              RecordingPresentationPolicy.hudPhase(for: .requestingPermission) == .listening,
              RecordingPresentationPolicy.hudPhase(for: .listening) == .listening,
              RecordingPresentationPolicy.hudPhase(for: .processing) == .processing,
              RecordingPresentationPolicy.hudPhase(for: .success) == .success,
              RecordingPresentationPolicy.hudPhase(for: .failure) == .failure else {
            throw TestFailure(description: "dictation lifecycle did not map to the expected HUD")
        }
    }),
    ("publishes one consistent presentation snapshot", {
        let listening = DictationPresentation(
            lifecycleState: .listening,
            audioLevel: 1.5,
            isAIRewriting: false
        )
        let processing = DictationPresentation(
            lifecycleState: .processing,
            audioLevel: 1,
            isAIRewriting: false
        )
        let rewriting = DictationPresentation(
            lifecycleState: .idle,
            audioLevel: 0,
            isAIRewriting: true
        )
        guard listening.isRecording,
              listening.hudPhase == .listening,
              listening.audioLevel == 1,
              processing.isRecording == false,
              processing.hudPhase == .processing,
              processing.audioLevel == 0,
              rewriting.isRecording == false,
              rewriting.hudPhase == .processing else {
            throw TestFailure(description: "presentation fields can drift out of sync")
        }
    }),
    ("queues the next recording while finalizing", {
        guard DictationControlPolicy.toggleAction(for: .idle) == .start,
              DictationControlPolicy.toggleAction(for: .requestingPermission) == .stop,
              DictationControlPolicy.toggleAction(for: .listening) == .stop,
              DictationControlPolicy.toggleAction(for: .processing)
                == .startWhenReady,
              DictationControlPolicy.toggleAction(for: .success) == .start,
              DictationControlPolicy.toggleAction(for: .failure) == .start else {
            throw TestFailure(
                description: "next dictation was discarded while finalizing"
            )
        }
    }),
    ("toggles and consumes one deferred recording start", {
        var deferredStart = DeferredRecordingStart()
        guard deferredStart.toggle(),
              deferredStart.isPending,
              deferredStart.toggle() == false,
              deferredStart.isPending == false,
              deferredStart.consume() == false else {
            throw TestFailure(
                description: "a second Fn press did not cancel the deferred start"
            )
        }

        guard deferredStart.toggle(),
              deferredStart.consume(),
              deferredStart.isPending == false,
              deferredStart.consume() == false else {
            throw TestFailure(
                description: "the deferred start was not consumed exactly once"
            )
        }
    }),
    ("keeps the last external target when Hushword becomes active", {
        var selector = TargetApplicationSelector(ownProcessIdentifier: 100)
        guard selector.observe(
            processIdentifier: 200,
            isRegularApplication: true,
            isTerminated: false
        ),
        selector.selectedProcessIdentifier == 200 else {
            throw TestFailure(description: "external target was not remembered")
        }

        guard selector.observe(
            processIdentifier: 100,
            isRegularApplication: false,
            isTerminated: false
        ) == false,
        selector.selectedProcessIdentifier == 200 else {
            throw TestFailure(description: "Hushword replaced the external target")
        }
    }),
    ("locks the paste target for the duration of a recording", {
        var selector = TargetApplicationSelector(ownProcessIdentifier: 100)
        _ = selector.observe(
            processIdentifier: 200,
            isRegularApplication: true,
            isTerminated: false
        )
        selector.lockSelection()
        guard selector.observe(
            processIdentifier: 300,
            isRegularApplication: true,
            isTerminated: false
        ) == false,
        selector.selectedProcessIdentifier == 200 else {
            throw TestFailure(description: "recording target changed before paste completed")
        }

        selector.unlockSelection()
        guard selector.observe(
            processIdentifier: 300,
            isRegularApplication: true,
            isTerminated: false
        ),
        selector.selectedProcessIdentifier == 300 else {
            throw TestFailure(description: "paste target stayed locked after completion")
        }
    }),
    ("waits until the target application is active before pasting", {
        var state = PasteActivationState(maximumChecks: 3)
        guard state.next(targetIsActive: false) == .retry,
              state.next(targetIsActive: false) == .retry,
              state.next(targetIsActive: true) == .paste else {
            throw TestFailure(description: "paste was sent before the target became active")
        }
    }),
    ("gives up instead of pasting into the wrong application", {
        var state = PasteActivationState(maximumChecks: 2)
        guard state.next(targetIsActive: false) == .retry,
              state.next(targetIsActive: false) == .giveUp else {
            throw TestFailure(description: "paste retry policy did not stop safely")
        }
    }),
    ("never prompts for accessibility without an explicit user action", {
        guard AutomaticPastePermissionPolicy.shouldRequest(for: .automatic) == false,
              AutomaticPastePermissionPolicy.shouldRequest(for: .userInitiated) else {
            throw TestFailure(description: "accessibility could be prompted automatically")
        }
    }),
    ("uses the highest-accuracy dictation recognition settings", {
        let policy = SpeechRecognitionPolicy.highAccuracy
        guard policy.requiresOnDeviceRecognition == false,
              policy.addsPunctuation else {
            throw TestFailure(description: "speech recognition is still configured for lower accuracy")
        }
    }),
    ("maps microphone energy to a stable HUD level", {
        guard AudioLevelPolicy.normalizedLevel(meanSquare: 0) == 0,
              AudioLevelPolicy.normalizedLevel(meanSquare: 0.0001) > 0,
              AudioLevelPolicy.normalizedLevel(meanSquare: 1) == 1,
              AudioLevelPolicy.smoothedLevel(previous: 0.2, current: 1) > 0.2,
              AudioLevelPolicy.smoothedLevel(previous: 0.2, current: 1) < 1 else {
            throw TestFailure(description: "microphone energy did not produce a bounded responsive HUD level")
        }
    }),
    ("drives every listening waveform bar from microphone level", {
        let silent = AudioWaveformPolicy.barHeights(level: 0)
        let speaking = AudioWaveformPolicy.barHeights(level: 1)
        guard silent.count == 5,
              speaking.count == 5,
              zip(silent, speaking).allSatisfy({ $0 < $1 }),
              speaking[2] == speaking.max(),
              silent.allSatisfy({ $0 >= 3 }),
              speaking.allSatisfy({ $0 <= 20 }) else {
            throw TestFailure(description: "waveform bars are not bounded by real microphone level")
        }
    }),
    ("allows whole-recording Apple recognition to finish after stop", {
        guard AppleFinalizationPolicy.wholeRecordingTimeoutNanoseconds
                >= 10_000_000_000 else {
            throw TestFailure(
                description: "whole-recording Apple recognition can still be cut off early"
            )
        }
    }),
    ("normalizes recognition vocabulary for both speech backends", {
        let terms = SpeechRecognitionVocabularyPolicy.normalizedTerms(
            [" RL ", "random signal", "", "RL", "fine-tuning"],
            maximumCount: 3
        )
        guard terms == ["RL", "random signal", "fine-tuning"] else {
            throw TestFailure(description: "recognition vocabulary was not normalized: \(terms)")
        }
    }),
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
    ("feeds terminology hints into the existing Whisper prompt", {
        let context = DictationContext(
            personalDictionaryText: "",
            historyTexts: [
                "我们继续测试 large-v3-turbo Q5。",
                "large-v3-turbo Q5 的结果已经稳定。",
            ]
        )
        let fields = WhisperRequestPolicy.fields(
            localeIdentifier: "zh-CN",
            contextualStrings: context.recognitionTerms
        )
        guard fields["prompt"]?.contains("large-v3-turbo Q5") == true else {
            throw TestFailure(
                description: "terminology hints did not reach the existing Whisper prompt"
            )
        }
    }),
    ("uses the multilingual final transcript instead of English phonetic guesses", {
        let appleTranscript = "使用 random sick know 再 fine two lin，所以我们能发吗？"
        let multilingualTranscript = "使用 random signal，在 fine-tuning 的情况下，所以我们能发 paper 吗？"
        let selected = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: multilingualTranscript,
            appleTranscript: appleTranscript,
            contextualStrings: ["random signal", "fine-tuning", "paper"]
        )
        guard selected == multilingualTranscript,
              selected.contains("random signal"),
              selected.contains("fine-tuning"),
              selected.contains("paper") else {
            throw TestFailure(description: "English terminology was not preserved: \(selected)")
        }
    }),
    ("falls back to the Apple transcript when multilingual recognition fails", {
        let appleTranscript = "现在只是说这个定义是怎么回事？"
        guard WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: " \n",
            appleTranscript: appleTranscript,
            contextualStrings: []
        ) == appleTranscript else {
            throw TestFailure(description: "multilingual fallback lost the Apple transcript")
        }
    }),
    ("maps selected locales to Whisper language codes", {
        guard WhisperLanguagePolicy.languageCode(
            for: "zh-CN"
        ) == "zh",
        WhisperLanguagePolicy.languageCode(
            for: "en-US"
        ) == "en",
        WhisperLanguagePolicy.languageCode(
            for: "ja-JP"
        ) == "ja",
        WhisperLanguagePolicy.languageCode(
            for: "ko-KR"
        ) == "ko",
        WhisperLanguagePolicy.languageCode(
            for: ""
        ) == "auto",
        WhisperLanguagePolicy.languageCode(
            for: "fr-FR"
        ) == "auto" else {
            throw TestFailure(description: "selected locale was not mapped safely")
        }
    }),
    ("builds a locale-aware greedy Whisper command with terminology context", {
        let arguments = WhisperCommandPolicy.arguments(
            modelPath: "/models/large.bin",
            audioPath: "/tmp/recording.wav",
            localeIdentifier: "zh-CN",
            contextualStrings: ["RL", "random signal", "fine-tuning", "paper"]
        )
        guard arguments.contains("/models/large.bin"),
              arguments.contains("/tmp/recording.wav"),
              arguments.contains("zh"),
              arguments.contains("-bo"),
              arguments.contains("1"),
              arguments.contains("-bs"),
              arguments.contains(where: {
                  $0.contains("random signal")
                      && $0.contains("fine-tuning")
                      && $0.contains("paper")
              }) else {
            throw TestFailure(description: "Whisper command omitted bilingual context: \(arguments)")
        }
    }),
    ("prefers the validated Q5 Whisper baseline while retaining higher precision fallbacks", {
        guard WhisperModelPolicy.preferredModelNames == [
            "ggml-large-v3-turbo-q5_0.bin",
            "ggml-large-v3-turbo-q8_0.bin",
            "ggml-large-v3-turbo.bin",
        ] else {
            throw TestFailure(description: "validated Whisper model order regressed")
        }
    }),
    ("prewarms a persistent local Whisper server", {
        let arguments = WhisperServerPolicy.arguments(
            modelPath: "/models/large-q8.bin",
            port: 18_188,
            contextualStrings: ["RL", "random signal", "fine-tuning", "paper"]
        )
        guard arguments.contains("/models/large-q8.bin"),
              arguments.contains("18188"),
              arguments.contains("auto"),
              arguments.contains(where: {
                  $0.contains("random signal")
                      && $0.contains("fine-tuning")
                      && $0.contains("paper")
              }) else {
            throw TestFailure(description: "persistent Whisper server omitted accuracy settings: \(arguments)")
        }
    }),
    ("builds locale-aware greedy Whisper request fields", {
        let fields = WhisperRequestPolicy.fields(
            localeIdentifier: "en-US",
            contextualStrings: ["random signal", "fine-tuning", "paper"]
        )
        guard fields["language"] == "en",
              fields["beam_size"] == "1",
              fields["best_of"] == "1",
              fields["temperature"] == "0.0",
              fields["temperature_inc"] == "0.2",
              fields["no_speech_thold"] == "0.6",
              fields["response_format"] == "verbose_json",
              fields["prompt"]?.contains("random signal") == true,
              fields["prompt"]?.contains("fine-tuning") == true,
              fields["prompt"]?.contains("paper") == true,
              fields["audio_ctx"] == nil else {
            throw TestFailure(description: "Whisper request lost validated decoding settings: \(fields)")
        }
    }),
    ("builds a natural retry prompt from existing terminology", {
        let fields = WhisperRequestPolicy.retryFields(
            localeIdentifier: "zh-CN",
            contextualStrings: [
                "ByteDance",
                "Hushword",
                "Typeless",
                "criteria",
                "fine-tuning",
                "paper",
                "random signal",
            ]
        )
        let prompt = fields["prompt"] ?? ""
        guard fields["response_format"] == "verbose_json",
              prompt.contains("使用 random signal"),
              prompt.contains("fine-tuning"),
              prompt.contains("发 paper"),
              prompt.contains("meet criteria"),
              prompt.contains("ByteDance"),
              prompt.contains("Hushword"),
              prompt.contains("Typeless") else {
            throw TestFailure(description: "retry prompt lost natural terminology context: \(fields)")
        }
    }),
    ("retries only a cluster of low-confidence spoken words", {
        let isolated = [
            WhisperWordConfidence(text: "我们", probability: 0.4),
            WhisperWordConfidence(text: "已经", probability: 0.99),
            WhisperWordConfidence(text: "做了", probability: 0.99),
            WhisperWordConfidence(text: "不是", probability: 0.34),
        ]
        let clustered = isolated + [
            WhisperWordConfidence(text: "这", probability: 0.35),
            WhisperWordConfidence(text: "词", probability: 0.45),
        ]
        guard WhisperConfidenceRetryPolicy.shouldRetry(words: isolated) == false,
              WhisperConfidenceRetryPolicy.shouldRetry(words: clustered) else {
            throw TestFailure(description: "low-confidence retry trigger is too broad or too weak")
        }
    }),
    ("accepts a nearby higher-confidence retry that restores terminology", {
        let primary = WhisperTranscriptCandidate(
            text: "所以我们能发这词吗？",
            words: [
                WhisperWordConfidence(text: "所以", probability: 0.99),
                WhisperWordConfidence(text: "我们", probability: 0.99),
                WhisperWordConfidence(text: "能", probability: 0.99),
                WhisperWordConfidence(text: "发", probability: 0.94),
                WhisperWordConfidence(text: "这", probability: 0.35),
                WhisperWordConfidence(text: "词", probability: 0.45),
                WhisperWordConfidence(text: "吗", probability: 0.98),
            ]
        )
        let retry = WhisperTranscriptCandidate(
            text: "所以我们能发 paper 吗？",
            words: [
                WhisperWordConfidence(text: "所以", probability: 0.99),
                WhisperWordConfidence(text: "我们", probability: 0.99),
                WhisperWordConfidence(text: "能", probability: 0.99),
                WhisperWordConfidence(text: "发", probability: 0.96),
                WhisperWordConfidence(text: "paper", probability: 0.72),
                WhisperWordConfidence(text: "吗", probability: 0.99),
            ]
        )
        let selected = WhisperConfidenceRetryPolicy.select(
            primary: primary,
            retry: retry,
            contextualStrings: ["paper"]
        )
        guard selected == retry else {
            throw TestFailure(description: "safe contextual retry was rejected: \(selected)")
        }
    }),
    ("rejects a prompted retry that drifts from the recording", {
        let primary = WhisperTranscriptCandidate(
            text: "今天我们讨论发布计划。",
            words: [
                WhisperWordConfidence(text: "今天", probability: 0.92),
                WhisperWordConfidence(text: "我们", probability: 0.42),
                WhisperWordConfidence(text: "讨论", probability: 0.41),
                WhisperWordConfidence(text: "发布", probability: 0.93),
                WhisperWordConfidence(text: "计划", probability: 0.95),
            ]
        )
        let retry = WhisperTranscriptCandidate(
            text: "使用 random signal，在 fine-tuning 的情况下发 paper。",
            words: [
                WhisperWordConfidence(text: "使用", probability: 0.98),
                WhisperWordConfidence(text: "random", probability: 0.98),
                WhisperWordConfidence(text: "signal", probability: 0.98),
                WhisperWordConfidence(text: "fine-tuning", probability: 0.98),
                WhisperWordConfidence(text: "paper", probability: 0.98),
            ]
        )
        let selected = WhisperConfidenceRetryPolicy.select(
            primary: primary,
            retry: retry,
            contextualStrings: ["random signal", "fine-tuning", "paper"]
        )
        guard selected == primary else {
            throw TestFailure(description: "prompt drift replaced the recording: \(selected)")
        }
    }),
    ("only runs multilingual finalization when all local assets are ready", {
        guard BilingualFinalizationPolicy.shouldRun(
            executableExists: true,
            modelExists: true,
            recordingHasAudio: true
        ),
        BilingualFinalizationPolicy.shouldRun(
            executableExists: false,
            modelExists: true,
            recordingHasAudio: true
        ) == false,
        BilingualFinalizationPolicy.shouldRun(
            executableExists: true,
            modelExists: false,
            recordingHasAudio: true
        ) == false,
        BilingualFinalizationPolicy.shouldRun(
            executableExists: true,
            modelExists: true,
            recordingHasAudio: false
        ) == false else {
            throw TestFailure(description: "multilingual finalization readiness is unsafe")
        }
    }),
]

var failures = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(error)")
    }
}

guard failures == 0 else {
    exit(1)
}
