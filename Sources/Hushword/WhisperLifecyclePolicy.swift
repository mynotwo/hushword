import Foundation

package enum WhisperLifecyclePolicy {
    package static let idleShutdownNanoseconds: UInt64 = 120_000_000_000
}

package struct WhisperMemoryPressureState {
    private var activeTranscriptions = 0
    private var releaseWhenIdle = false

    package init() {}

    package mutating func beginTranscription() {
        activeTranscriptions += 1
    }

    package mutating func receivePressure() -> Bool {
        guard activeTranscriptions > 0 else { return true }
        releaseWhenIdle = true
        return false
    }

    package mutating func finishTranscription() -> Bool {
        activeTranscriptions = max(0, activeTranscriptions - 1)
        guard activeTranscriptions == 0, releaseWhenIdle else {
            return false
        }
        releaseWhenIdle = false
        return true
    }
}
