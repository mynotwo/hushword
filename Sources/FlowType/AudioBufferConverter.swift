import AVFoundation

package final class AudioBufferConverter {
    enum ConversionError: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    package init() {}

    package func convert(
        _ buffer: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != outputFormat else {
            return buffer
        }

        if converter == nil
            || converter?.inputFormat != inputFormat
            || converter?.outputFormat != outputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw ConversionError.cannotCreateConverter
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(
            (Double(buffer.frameLength) * ratio).rounded(.up)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw ConversionError.cannotCreateBuffer
        }

        var conversionError: NSError?
        var providedInput = false
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            throw ConversionError.conversionFailed(conversionError)
        }
        return outputBuffer
    }
}
