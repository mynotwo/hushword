import AVFoundation
import FlowTypeCore
import Foundation
import Speech

private func microphoneLevel(from buffer: AVAudioPCMBuffer) -> Double {
    guard let samples = buffer.floatChannelData?[0] else { return 0 }
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return 0 }

    let stride = max(1, frameCount / 256)
    var sum: Float = 0
    var sampleCount = 0
    for index in Swift.stride(from: 0, to: frameCount, by: stride) {
        let sample = samples[index]
        sum += sample * sample
        sampleCount += 1
    }
    guard sampleCount > 0 else { return 0 }
    return AudioLevelPolicy.normalizedLevel(
        meanSquare: sum / Float(sampleCount)
    )
}

private final class AudioActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var maximumLevel = 0.0

    func record(_ level: Double) {
        lock.lock()
        maximumLevel = max(maximumLevel, level)
        lock.unlock()
    }

    var detectedSpeech: Bool {
        lock.lock()
        defer { lock.unlock() }
        return maximumLevel >= 0.02
    }
}

package enum RecordingFinalizationPolicy {
    package static func shouldRecognize(
        hasRecordingFile: Bool,
        detectedSpeech _: Bool
    ) -> Bool {
        hasRecordingFile
    }
}

@MainActor
private final class WholeRecordingAppleSession {
    private var continuation: CheckedContinuation<String, Never>?
    var recognitionTask: SFSpeechRecognitionTask?
    var timeoutTask: Task<Void, Never>?
    var latestTranscript = ""

    init(continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    func finish(with transcript: String? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        continuation.resume(returning: transcript ?? latestTranscript)
    }
}

@MainActor
final class SpeechRecognitionService: SpeechCapturing {
    enum SpeechError: LocalizedError {
        case microphoneDenied
        case speechDenied
        case recognizerUnavailable
        case analyzerAudioFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Microphone permission is required."
            case .speechDenied:
                return "Speech Recognition permission is required."
            case .recognizerUnavailable:
                return "Speech recognizer is unavailable."
            case .analyzerAudioFormatUnavailable:
                return "Speech analyzer audio format is unavailable."
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private let whisperFinalizer = WhisperFinalizer()
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingLocaleIdentifier = ""
    private var recordingContextualStrings: [String] = []
    private var audioActivityTracker = AudioActivityTracker()
    private var wholeRecordingAppleSession: WholeRecordingAppleSession?

    func start(
        localeIdentifier: String,
        contextualStrings: [String],
        onAudioLevel: @escaping (Double) -> Void
    ) async throws {
        whisperFinalizer.prewarm()
        guard await requestMicrophonePermission() else {
            whisperFinalizer.finishActivityWithoutTranscription()
            throw SpeechError.microphoneDenied
        }
        guard await requestSpeechPermission() else {
            whisperFinalizer.finishActivityWithoutTranscription()
            throw SpeechError.speechDenied
        }

        stopCurrentAudioCapture()
        discardAudioRecording()
        cancelWholeRecordingAppleRecognition()
        audioActivityTracker = AudioActivityTracker()
        recordingLocaleIdentifier = localeIdentifier
        recordingContextualStrings = contextualStrings

        do {
            try startWholeRecordingCapture(onAudioLevel: onAudioLevel)
        } catch {
            recordingLocaleIdentifier = ""
            recordingContextualStrings = []
            whisperFinalizer.finishActivityWithoutTranscription()
            throw error
        }
    }

    func stop() async -> SpeechRecognitionResult {
        let clock = ContinuousClock()
        let stopStartedAt = clock.now
        stopCurrentAudioCapture()
        let audioURL = finishAudioRecording()
        let localeIdentifier = recordingLocaleIdentifier
        let contextualStrings = recordingContextualStrings
        let recordingHasSpeech = audioActivityTracker.detectedSpeech
        recordingLocaleIdentifier = ""
        recordingContextualStrings = []

        let shouldRecognize = RecordingFinalizationPolicy.shouldRecognize(
            hasRecordingFile: audioURL != nil,
            detectedSpeech: recordingHasSpeech
        )
        guard let audioURL, shouldRecognize else {
            if let audioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
            whisperFinalizer.finishActivityWithoutTranscription()
            let result = SpeechRecognitionResult(
                whisperTranscript: "",
                appleTranscript: nil
            )
            let snapshot = RecognitionTimingSnapshot(
                appleDuration: .zero,
                whisperDuration: nil,
                totalDuration: stopStartedAt.duration(to: clock.now),
                appleTranscript: "",
                whisperTranscript: nil,
                selectedTranscript: result.whisperTranscript
            )
            RecognitionTimingLogger.record(snapshot)
            return result
        }

        let appleTask = Task { [weak self] in
            let transcript = await self?.recognizeWholeRecordingWithApple(
                audioURL: audioURL,
                localeIdentifier: localeIdentifier,
                contextualStrings: contextualStrings
            ) ?? ""
            return (transcript, clock.now)
        }
        let whisperTask = Task { [whisperFinalizer] in
            let transcript = await whisperFinalizer.transcribe(
                audioURL: audioURL,
                localeIdentifier: localeIdentifier,
                contextualStrings: contextualStrings
            )
            return (transcript, clock.now)
        }

        let appleResult = await appleTask.value
        let whisperResult = await whisperTask.value
        let appleTranscript = appleResult.0
        let multilingualTranscript = whisperResult.0
        try? FileManager.default.removeItem(at: audioURL)
        let primary = normalized(multilingualTranscript).isEmpty
            ? appleTranscript
            : normalized(multilingualTranscript)
        let alternative = appleTranscript.isEmpty || appleTranscript == primary
            ? nil
            : appleTranscript
        let result = SpeechRecognitionResult(
            whisperTranscript: primary,
            appleTranscript: alternative
        )
        let snapshot = RecognitionTimingSnapshot(
            appleDuration: stopStartedAt.duration(to: appleResult.1),
            whisperDuration: stopStartedAt.duration(to: whisperResult.1),
            totalDuration: stopStartedAt.duration(to: clock.now),
            appleTranscript: appleTranscript,
            whisperTranscript: multilingualTranscript,
            selectedTranscript: result.whisperTranscript
        )
        RecognitionTimingLogger.record(snapshot)
        return result
    }

    func shutdown() {
        stopCurrentAudioCapture()
        discardAudioRecording()
        recordingLocaleIdentifier = ""
        recordingContextualStrings = []
        cancelWholeRecordingAppleRecognition()
        whisperFinalizer.shutdown()
    }

    private func startWholeRecordingCapture(
        onAudioLevel: @escaping (Double) -> Void
    ) throws {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        AudioInputDeviceSelector.configure(inputNode)
        let format = inputNode.outputFormat(forBus: 0)
        let recording = try startAudioRecording()
        let activityTracker = audioActivityTracker
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: format
        ) { buffer, _ in
            if let whisperBuffer = try? recording.converter.convert(
                buffer,
                to: recording.file.processingFormat
            ) {
                try? recording.file.write(from: whisperBuffer)
            }
            let level = microphoneLevel(from: buffer)
            activityTracker.record(level)
            Task { @MainActor in onAudioLevel(level) }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func recognizeWholeRecordingWithApple(
        audioURL: URL,
        localeIdentifier: String,
        contextualStrings: [String]
    ) async -> String {
        let legacyTranscript = await recognizeWholeRecordingWithLegacyApple(
            audioURL: audioURL,
            localeIdentifier: localeIdentifier,
            contextualStrings: contextualStrings
        )
        guard legacyTranscript.isEmpty,
              #available(macOS 26.0, *) else {
            return legacyTranscript
        }
        let modernTranscript = await AppleModernDictationRecognizer.transcribe(
            audioURL: audioURL,
            localeIdentifier: localeIdentifier,
            contextualStrings: contextualStrings
        )
        return modernTranscript
    }

    private func recognizeWholeRecordingWithLegacyApple(
        audioURL: URL,
        localeIdentifier: String,
        contextualStrings: [String]
    ) async -> String {
        guard let recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: localeIdentifier)
        ), recognizer.isAvailable else {
            return ""
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        let policy = SpeechRecognitionPolicy.highAccuracy
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = policy.requiresOnDeviceRecognition
        request.addsPunctuation = policy.addsPunctuation
        request.taskHint = .dictation
        request.contextualStrings = Array(contextualStrings.prefix(100))

        return await withCheckedContinuation { continuation in
            let session = WholeRecordingAppleSession(
                continuation: continuation
            )
            wholeRecordingAppleSession = session
            session.recognitionTask = recognizer.recognitionTask(
                with: request
            ) { [weak self, weak session] result, error in
                Task { @MainActor in
                    guard let self,
                          let session,
                          self.wholeRecordingAppleSession === session else {
                        return
                    }
                    if let result {
                        let firstTranscription = result.bestTranscription
                        let selectedText =
                            AppleTranscriptionCandidateSelector.select(
                                candidates: result.transcriptions.map(
                                    \.formattedString
                                ),
                                firstCandidateSegments:
                                    firstTranscription.segments.map {
                                        AppleCandidateSegmentEvidence(
                                            utf16Range: $0.substringRange,
                                            confidence: $0.confidence
                                        )
                                    }
                            )
                        let transcription = result.transcriptions.first {
                            $0.formattedString == selectedText
                        } ?? firstTranscription
                        session.latestTranscript = transcription.formattedString
                    }
                    if result?.isFinal == true || error != nil {
                        session.finish()
                        self.wholeRecordingAppleSession = nil
                    }
                }
            }
            session.timeoutTask = Task { [weak self, weak session] in
                try? await Task.sleep(
                    nanoseconds: AppleFinalizationPolicy
                        .wholeRecordingTimeoutNanoseconds
                )
                guard !Task.isCancelled else { return }
                guard let self,
                      let session,
                      self.wholeRecordingAppleSession === session else {
                    return
                }
                session.finish()
                self.wholeRecordingAppleSession = nil
            }
        }
    }

    private func cancelWholeRecordingAppleRecognition() {
        wholeRecordingAppleSession?.finish()
        wholeRecordingAppleSession = nil
    }

    private func normalized(_ transcript: String?) -> String {
        transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func stopCurrentAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func startAudioRecording() throws -> (
        file: AVAudioFile,
        converter: AudioBufferConverter
    ) {
        discardAudioRecording()
        guard let outputFormat = WhisperAudioPolicy.makeFormat() else {
            throw SpeechError.analyzerAudioFormatUnavailable
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtype-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: WhisperAudioPolicy.sampleRate,
            AVNumberOfChannelsKey: WhisperAudioPolicy.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: !WhisperAudioPolicy.isInterleaved,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let converter = AudioBufferConverter()
        recordingFile = file
        recordingURL = url
        return (file, converter)
    }

    private func finishAudioRecording() -> URL? {
        recordingFile = nil
        let url = recordingURL
        recordingURL = nil
        return url
    }

    private func discardAudioRecording() {
        recordingFile = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
