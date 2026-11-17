import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    @MainActor
    static func usesModernAppleDictationOnlyWhenSupported() async throws {
        guard AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: true,
            localeIsSupported: true
        ) == .modernDictation,
        AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: false,
            localeIsSupported: true
        ) == .legacy,
        AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: true,
            localeIsSupported: false
        ) == .legacy else {
            throw TestFailure(
                description: "modern Apple dictation fallback policy is unsafe"
            )
        }
    }

    @MainActor
    static func selectsOnlyStronglySupportedAppleAlternative() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "这么赚的话，他早上可以不接单呀",
            "这么拽的话，他早上可以不接单呀",
        ]
        let scores = [
            candidates[0]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.72,
                changedTermRelevance: 0.70
            ),
            candidates[1]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.91,
                changedTermRelevance: 0.90
            ),
            candidates[2]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.63,
                changedTermRelevance: 0.95
            ),
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.423
                ),
            ],
            semanticScore: { candidate, _, _ in scores[candidate] }
        )

        guard selected == candidates[1],
              candidates.contains(selected) else {
            throw TestFailure(
                description: "selector generated or chose an unsupported transcript: \(selected)"
            )
        }
    }

    @MainActor
    static func keepsFirstAppleCandidateWhenSemanticEvidenceIsWeak() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "这么赚的话，他早上可以不接单呀",
            "这么拽的话，他早上可以不接单呀",
        ]
        let scores = [
            candidates[0]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.720,
                changedTermRelevance: 0.720
            ),
            candidates[1]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.725,
                changedTermRelevance: 0.725
            ),
            candidates[2]: AppleCandidateSemanticScore(
                sentenceRelevance: 0.719,
                changedTermRelevance: 0.719
            ),
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.423
                ),
            ],
            semanticScore: { candidate, _, _ in scores[candidate] }
        )

        guard selected == candidates[0] else {
            throw TestFailure(
                description: "weak evidence replaced Apple's first transcript: \(selected)"
            )
        }
    }

    @MainActor
    static func keepsFirstAppleCandidateWhenChangedSegmentIsConfident() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "这么赚的话，他早上可以不接单呀",
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.92
                ),
            ],
            semanticScore: { candidate, _, _ in
                AppleCandidateSemanticScore(
                    sentenceRelevance: candidate == candidates[1] ? 1.0 : 0.0,
                    changedTermRelevance: candidate == candidates[1] ? 1.0 : 0.0
                )
            }
        )

        guard selected == candidates[0] else {
            throw TestFailure(
                description: "a confident Apple segment was unnecessarily replaced"
            )
        }
    }

    @MainActor
    static func rejectsStructurallyDriftingAppleAlternative() async throws {
        let candidates = [
            "这么转的话，他早上可以不接单呀",
            "他决定明天早上完全不再接任何订单",
        ]
        let selected = AppleTranscriptionCandidateSelector.select(
            candidates: candidates,
            firstCandidateSegments: [
                AppleCandidateSegmentEvidence(
                    utf16Range: NSRange(location: 2, length: 1),
                    confidence: 0.423
                ),
            ],
            semanticScore: { candidate, _, _ in
                AppleCandidateSemanticScore(
                    sentenceRelevance: candidate == candidates[1] ? 1.0 : 0.0,
                    changedTermRelevance: candidate == candidates[1] ? 1.0 : 0.0
                )
            }
        )

        guard selected == candidates[0] else {
            throw TestFailure(
                description: "a structurally different transcript replaced Apple's first choice"
            )
        }
    }
}
