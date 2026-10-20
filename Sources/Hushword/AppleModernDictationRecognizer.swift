import AVFoundation
import HushwordCore
import Foundation
import Speech

@available(macOS 26.0, *)
package enum AppleModernDictationRecognizer {
    package static func transcribe(
        audioURL: URL,
        localeIdentifier: String,
        contextualStrings: [String]
    ) async -> String {
        let requestedLocale = Locale(identifier: localeIdentifier)
        let supportedLocale = await DictationTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        )
        guard AppleSpeechBackendPolicy.preferredBackend(
            osSupportsModernDictation: true,
            localeIsSupported: supportedLocale != nil
        ) == .modernDictation,
        let locale = supportedLocale else {
            return ""
        }
        let installedLocales = await DictationTranscriber.installedLocales
        guard installedLocales.contains(where: {
            $0.identifier == locale.identifier
        }) else {
            return ""
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .longDictation
        )
        let resultsTask = Task {
            var transcript = AttributedString()
            do {
                for try await result in transcriber.results
                    where result.isFinal {
                    transcript.append(result.text)
                }
            } catch {
                return ""
            }
            return String(transcript.characters)
        }

        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let context = AnalysisContext()
            context.contextualStrings[.general] =
                SpeechRecognitionVocabularyPolicy.normalizedTerms(
                    contextualStrings
                )
            try await analyzer.setContext(context)
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return await resultsTask.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        } catch {
            resultsTask.cancel()
            return ""
        }
    }
}
