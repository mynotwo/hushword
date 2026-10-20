import Foundation

public struct DictationContext: Sendable {
    private static let maximumTerminologyHints = 30
    private static let builtInTerms = [
        "AI",
        "LLM",
        "RL",
        "Agent",
        "ByteDance",
        "Flex",
        "FlowType",
        "Typeless",
        "criteria",
        "meet criteria",
        "paper",
        "prompt",
        "random signal",
        "fine-tuning",
        "reward",
        "reward model",
    ]

    public let dictionary: [String: String]
    public let terminologyHints: [String]
    public let recognitionTerms: [String]

    public init(
        personalDictionaryText: String,
        learnedCorrections: [LearnedCorrection] = [],
        historyTexts: [String] = []
    ) {
        let manualDictionary: [String: String] = personalDictionaryText
            .split(separator: "\n")
            .reduce(into: [:]) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2,
                      !parts[0].isEmpty,
                      !parts[1].isEmpty else {
                    return
                }
                result[parts[0]] = parts[1]
            }
        let manualKeys = Set(manualDictionary.keys.map { $0.lowercased() })
        dictionary = learnedCorrections.reduce(
            into: manualDictionary
        ) { result, correction in
            let observed = correction.observed.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let preferred = correction.preferred.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !observed.isEmpty,
                  !preferred.isEmpty,
                  !manualKeys.contains(observed.lowercased()) else {
                return
            }
            result[observed] = preferred
        }
        terminologyHints = Self.terminologyHints(from: historyTexts)
        recognitionTerms = Array(
            Set(
                Self.builtInTerms
                    + dictionary.flatMap { [$0.key, $0.value] }
                    + terminologyHints
            )
        ).sorted()
    }

    private static func terminologyHints(
        from historyTexts: [String]
    ) -> [String] {
        let pattern = #"\b(?:[A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)+(?:\s+[A-Za-z]*\d[A-Za-z0-9.-]*)?|[A-Za-z][A-Za-z0-9]*\s+\d+(?:\.\d+)+|[A-Z][A-Z0-9]{1,9}|[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]*)*)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var counts: [String: Int] = [:]
        var spellings: [String: String] = [:]
        for text in historyTexts {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let terms = Set(expression.matches(in: text, range: range).compactMap {
                Range($0.range, in: text).map {
                    String(text[$0]).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
            })
            for term in terms where !term.isEmpty {
                let key = term.lowercased()
                counts[key, default: 0] += 1
                spellings[key, default: term] = term
            }
        }

        return counts.compactMap { key, count -> (String, Int)? in
            guard let spelling = spellings[key] else { return nil }
            let threshold = isDistinctiveTechnicalTerm(spelling) ? 2 : 3
            return count >= threshold ? (spelling, count) : nil
        }
        .sorted {
            $0.1 == $1.1
                ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
                : $0.1 > $1.1
        }
        .prefix(maximumTerminologyHints)
        .map(\.0)
    }

    private static func isDistinctiveTechnicalTerm(_ term: String) -> Bool {
        if term.contains(where: { $0.isNumber })
            || term.contains("-")
            || term.contains(".") {
            return true
        }
        let letters = term.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }
}
