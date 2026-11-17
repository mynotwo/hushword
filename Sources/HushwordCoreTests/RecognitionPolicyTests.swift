import HushwordCore
import Foundation

let finalTranscriptPolicyTests: [(String, () throws -> Void)] = [
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
]

let recognitionSettingsTests: [(String, () throws -> Void)] = [
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
]

let whisperPolicyTests: [(String, () throws -> Void)] = [
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
