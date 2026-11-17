import AVFoundation
import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    @MainActor
    static func recordsWhisperAudioAs16kHzMonoInt16() async throws {
        guard WhisperAudioPolicy.sampleRate == 16_000,
              WhisperAudioPolicy.channelCount == 1,
              WhisperAudioPolicy.commonFormat == .pcmFormatInt16,
              WhisperAudioPolicy.isInterleaved,
              let format = WhisperAudioPolicy.makeFormat(),
              format.sampleRate == 16_000,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16,
              format.isInterleaved else {
            throw TestFailure(description: "Whisper recording format regressed")
        }
    }

    @MainActor
    static func recognizesRecordingWhenHUDLevelMissesSpeech() async throws {
        guard RecordingFinalizationPolicy.shouldRecognize(
            hasRecordingFile: true,
            detectedSpeech: false
        ) else {
            throw TestFailure(
                description: "HUD audio level incorrectly discarded a complete recording"
            )
        }
    }

    @MainActor
    static func respectsUsersDefaultMicrophone() async throws {
        let devices = [
            AudioInputDeviceCandidate(
                identifier: 41,
                hasInput: true,
                isBuiltIn: false
            ),
            AudioInputDeviceCandidate(
                identifier: 79,
                hasInput: true,
                isBuiltIn: true
            ),
        ]
        guard AudioInputDevicePolicy.preferredDeviceIdentifier(
            devices: devices,
            defaultDeviceIdentifier: 41
        ) == 41 else {
            throw TestFailure(
                description: "Hushword overrode the user's working default microphone"
            )
        }
    }

    @MainActor
    static func convertsMicrophoneAudioToWhisperRecordingFormat() async throws {
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ),
        let outputFormat = WhisperAudioPolicy.makeFormat(),
        let input = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: 4_800
        ) else {
            throw TestFailure(description: "could not create audio conversion fixtures")
        }
        input.frameLength = 4_800
        if let samples = input.floatChannelData?[0] {
            for index in 0..<Int(input.frameLength) {
                samples[index] = sin(Float(index) * 0.05) * 0.25
            }
        }

        let output = try AudioBufferConverter().convert(
            input,
            to: outputFormat
        )
        guard output.format.sampleRate == 16_000,
              output.format.channelCount == 1,
              output.format.commonFormat == .pcmFormatInt16,
              output.format.isInterleaved,
              (1_590...1_610).contains(Int(output.frameLength)) else {
            throw TestFailure(
                description: "unexpected Whisper buffer: "
                    + "\(output.format), frames=\(output.frameLength)"
            )
        }
    }

    @MainActor
    static func preservesDurationAcrossConsecutiveAudioBuffers() async throws {
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ),
        let outputFormat = WhisperAudioPolicy.makeFormat() else {
            throw TestFailure(description: "could not create continuous conversion formats")
        }

        let converter = AudioBufferConverter()
        var outputFrames = 0
        for bufferIndex in 0..<47 {
            guard let input = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: 1_024
            ) else {
                throw TestFailure(description: "could not create continuous input buffer")
            }
            input.frameLength = 1_024
            if let samples = input.floatChannelData?[0] {
                for frameIndex in 0..<Int(input.frameLength) {
                    let sampleIndex = bufferIndex * 1_024 + frameIndex
                    samples[frameIndex] = sin(Float(sampleIndex) * 0.03) * 0.25
                }
            }
            outputFrames += Int(
                try converter.convert(input, to: outputFormat).frameLength
            )
        }

        let expectedFrames = Int(
            (Double(47 * 1_024) / 3.0).rounded()
        )
        guard abs(outputFrames - expectedFrames) <= 2 else {
            throw TestFailure(
                description: "continuous conversion lost duration: "
                    + "expected \(expectedFrames), got \(outputFrames)"
            )
        }
    }
}
