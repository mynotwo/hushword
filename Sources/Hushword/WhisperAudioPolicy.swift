import AVFoundation

package enum WhisperAudioPolicy {
    package static let sampleRate = 16_000.0
    package static let channelCount: AVAudioChannelCount = 1
    package static let commonFormat: AVAudioCommonFormat = .pcmFormatInt16
    package static let isInterleaved = true

    package static func makeFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: isInterleaved
        )
    }
}
