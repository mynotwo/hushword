import Foundation

public struct TranscriptCleaner: Sendable {
    private let dictionary: [String: String]

    public init(dictionary: [String: String] = [:]) {
        self.dictionary = dictionary
    }

    public func clean(_ transcript: String) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        text = applySelfCorrections(to: text)
        text = removeFillers(from: text)
        text = removeAdjacentRepetitions(from: text)
        text = applyDictionary(to: text)
        text = applySpokenFormatting(to: text)
        text = formatExplicitLists(in: text)
        text = normalizeSpacing(in: text)
        return addTerminalPunctuation(to: text)
    }

    private func applySelfCorrections(to text: String) -> String {
        let EnglishPattern = #"(?i)^(.+\b(?:on|at|in|for|to|with)\s+)(.+?)\s+(?:no actually|no, actually|actually no|sorry|rather)\s+(.+)$"#
        var output = replacing(pattern: EnglishPattern, in: text, template: "$1$3")
        output = applyConservativeChineseSelfCorrection(to: output)
        return output
    }

    private func applyConservativeChineseSelfCorrection(
        to text: String
    ) -> String {
        let markers = ["不对", "说错了", "改成", "应该是"]
        guard let match = markers.compactMap({ marker -> (
            range: Range<String.Index>,
            marker: String
        )? in
            text.range(of: marker).map { ($0, marker) }
        }).min(by: { $0.range.lowerBound < $1.range.lowerBound }) else {
            return text
        }

        let left = String(text[..<match.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(text[match.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return text }

        let sharedSuffix = longestSharedSuffix(left, right)
        guard sharedSuffix.count >= 2,
              right.count > sharedSuffix.count else {
            return text
        }
        let replacementPrefixCount = right.count - sharedSuffix.count
        let replacedPhraseCount = replacementPrefixCount + sharedSuffix.count
        guard left.count >= replacedPhraseCount else { return text }
        return String(left.dropLast(replacedPhraseCount)) + right
    }

    private func longestSharedSuffix(
        _ lhs: String,
        _ rhs: String
    ) -> String {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        let maximumCount = min(lhsCharacters.count, rhsCharacters.count)
        var sharedCount = 0
        while sharedCount < maximumCount,
              lhsCharacters[lhsCharacters.count - sharedCount - 1]
                == rhsCharacters[rhsCharacters.count - sharedCount - 1] {
            sharedCount += 1
        }
        return String(rhsCharacters.suffix(sharedCount))
    }

    private func removeFillers(from text: String) -> String {
        var output = replacing(
            pattern: #"(?i)(?:^|\s)\b(?:um+|uh+|erm+|hmm+|you know)\b(?=\s|$)"#,
            in: text,
            template: " "
        )
        output = replacing(
            pattern: #"(^|\s)(?:嗯+|呃+|额+|那个)(?=\s|$)"#,
            in: output,
            template: "$1"
        )
        output = replacing(
            pattern: #"^(?:(?:(?:哎呀|哎|唉)(?=[，,、。！？!?\s])|(?:嗯+|呃+|额+))[，,、。！？!?\s]*)+"#,
            in: output,
            template: ""
        )
        output = replacing(
            pattern: #"([，,。！？!?\s])(?:嗯+|呃+|额+)(?=[，,。！？!?\s])"#,
            in: output,
            template: "$1"
        )
        return output
    }

    private func removeAdjacentRepetitions(from text: String) -> String {
        var output = text
        let pattern = #"(?i)\b([\p{L}\p{N}']+)(?:\s+\1\b)+"#
        while true {
            let next = replacing(pattern: pattern, in: output, template: "$1")
            guard next != output else { break }
            output = next
        }
        let repeatedDiscoursePhrases = [
            "我觉得", "我", "这个", "那个", "然后", "所以",
            "但是", "而且", "就是", "其实", "我们",
        ]
        for phrase in repeatedDiscoursePhrases.sorted(
            by: { $0.count > $1.count }
        ) {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            output = replacing(
                pattern: "(\(escaped))(?:[，,、\\s]*\\1)+",
                in: output,
                template: "$1"
            )
        }
        return output
    }

    private func applyDictionary(to text: String) -> String {
        dictionary
            .sorted { $0.key.count > $1.key.count }
            .reduce(text) { current, entry in
                replacing(
                    pattern: NSRegularExpression.escapedPattern(for: entry.key),
                    in: current,
                    template: NSRegularExpression.escapedTemplate(for: entry.value),
                    options: [.caseInsensitive]
                )
            }
    }

    private func applySpokenFormatting(to text: String) -> String {
        let commands: [(String, String)] = [
            (#"(?i)\bnew (?:line|paragraph)\b|新的一行|换行|另起一行"#, "\n"),
            (#"(?i)\bquestion mark\b|问号"#, "?"),
            (#"(?i)\bexclamation mark\b|感叹号"#, "!"),
            (#"(?i)\bfull stop\b|\bperiod\b|句号"#, "。"),
            (#"(?i)\bcolon\b|冒号"#, "："),
            (#"(?i)\bsemicolon\b|分号"#, "；"),
            (#"(?i)\bcomma\b|逗号"#, "，"),
        ]

        var output = text
        for (pattern, replacement) in commands {
            output = replacing(pattern: pattern, in: output, template: replacement)
        }
        output = replacing(
            pattern: #"(?m)^[ \t]*(第[一二三四五六七八九十]+)\s+"#,
            in: output,
            template: "$1，"
        )
        return output
    }

    private func formatExplicitLists(in text: String) -> String {
        let pattern = #"^(.{0,24}?(?:三件事|三点|三个(?:想法|步骤|问题|要求)))[，,、：:\s]*(第一|首先)[，,、：:\s]*(.{2,}?)[，,、；;\s]*(第二|其次)[，,、：:\s]*(.{2,}?)[，,、；;\s]*(第三|最后)[，,、：:\s]*(.+?)[。！？.!?]?$"#
        return replacing(
            pattern: pattern,
            in: text,
            template: "$1：\n$2，$3；\n$4，$5；\n$6，$7"
        )
    }

    private func normalizeSpacing(in text: String) -> String {
        var output = replacing(
            pattern: #"＞+(?=\s*$)"#,
            in: text,
            template: text.contains(where: isCJK) ? "。" : "."
        )
        output = replacing(
            pattern: #"(吗|呢|么|嘛)＞+"#,
            in: output,
            template: "$1？"
        )
        output = replacing(
            pattern: #"＞+"#,
            in: output,
            template: "，"
        )
        output = replacing(pattern: #"[ \t]+"#, in: output, template: " ")
        output = replacing(pattern: #" *\n *"#, in: output, template: "\n")
        output = replacing(pattern: #"\n{3,}"#, in: output, template: "\n\n")
        output = normalizeCommaStyle(in: output)
        output = replacing(
            pattern: #"(?<=[\u{4E00}-\u{9FFF}])\s+(?=[\u{4E00}-\u{9FFF}])"#,
            in: output,
            template: ""
        )
        output = replacing(pattern: #"\s+([，。！？：；,.!?;:])"#, in: output, template: "$1")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeCommaStyle(in text: String) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "," else {
                output.append(character)
                index += 1
                continue
            }

            let previous = characters[..<index].last {
                !$0.isWhitespace
            }
            let next = characters[(index + 1)...].first {
                !$0.isWhitespace
            }
            guard previous.map(isCJK) == true || next.map(isCJK) == true else {
                output.append(character)
                index += 1
                continue
            }

            output.append("，")
            index += 1
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }
        return output
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }
    }

    private func addTerminalPunctuation(to text: String) -> String {
        guard let last = text.last, !".!?。！？".contains(last) else { return text }
        let lastIsCJK = isCJK(last)
        return text + (lastIsCJK ? "。" : ".")
    }

    private func replacing(
        pattern: String,
        in text: String,
        template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
