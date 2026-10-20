import HushwordCore
import Foundation

package struct SpeechRecognitionResult: Sendable {
    package let whisperTranscript: String
    package let appleTranscript: String?

    package init(
        whisperTranscript: String,
        appleTranscript: String?
    ) {
        self.whisperTranscript = whisperTranscript
        self.appleTranscript = appleTranscript
    }
}

@MainActor
package protocol SpeechCapturing: AnyObject {
    func start(
        localeIdentifier: String,
        contextualStrings: [String],
        onAudioLevel: @escaping (Double) -> Void
    ) async throws

    func stop() async -> SpeechRecognitionResult
    func shutdown()
}

@MainActor
package final class DictationEngine {
    private let speechCapture: any SpeechCapturing

    package init(speechCapture: any SpeechCapturing) {
        self.speechCapture = speechCapture
    }

    convenience init() {
        self.init(speechCapture: SpeechRecognitionService())
    }

    func start(
        localeIdentifier: String,
        context: DictationContext,
        onAudioLevel: @escaping (Double) -> Void
    ) async throws {
        try await speechCapture.start(
            localeIdentifier: localeIdentifier,
            contextualStrings: context.recognitionTerms,
            onAudioLevel: onAudioLevel
        )
    }

    package func finish(
        context: DictationContext
    ) async -> String {
        let cleaner = TranscriptCleaner(dictionary: context.dictionary)
        let recognitionResult = await speechCapture.stop()
        let selectedTranscript = WholeRecordingFinalTranscriptPolicy.select(
            whisperTranscript: recognitionResult.whisperTranscript,
            appleTranscript: recognitionResult.appleTranscript ?? "",
            contextualStrings: context.recognitionTerms
        )
        return cleaner.clean(selectedTranscript)
    }

    func shutdown() {
        speechCapture.shutdown()
    }
}
