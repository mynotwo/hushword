import Foundation

public enum DictationLifecycleState: Sendable {
    case idle
    case requestingPermission
    case listening
    case processing
    case success
    case failure
}

public enum DictationHUDPhase: Equatable, Sendable {
    case hidden
    case listening
    case processing
    case success
    case failure
}

public struct DictationPresentation: Equatable, Sendable {
    public let isRecording: Bool
    public let hudPhase: DictationHUDPhase
    public let audioLevel: Double

    public init(
        lifecycleState: DictationLifecycleState,
        audioLevel: Double,
        isAIRewriting: Bool = false
    ) {
        let isRecording = lifecycleState == .requestingPermission
            || lifecycleState == .listening
        self.isRecording = isRecording
        hudPhase = isAIRewriting
            ? .processing
            : RecordingPresentationPolicy.hudPhase(for: lifecycleState)
        self.audioLevel = isRecording
            ? min(1, max(0, audioLevel))
            : 0
    }
}

public enum DictationToggleAction: Equatable, Sendable {
    case start
    case stop
    case startWhenReady
}

public struct DeferredRecordingStart: Equatable, Sendable {
    public private(set) var isPending = false

    public init() {}

    @discardableResult
    public mutating func toggle() -> Bool {
        isPending.toggle()
        return isPending
    }

    @discardableResult
    public mutating func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}

public enum DictationControlPolicy {
    public static func toggleAction(
        for state: DictationLifecycleState
    ) -> DictationToggleAction {
        switch state {
        case .requestingPermission, .listening:
            return .stop
        case .processing:
            return .startWhenReady
        case .idle, .success, .failure:
            return .start
        }
    }
}

public enum RecordingPresentationPolicy {
    public static func shouldShowPopover(isRecording: Bool) -> Bool {
        !isRecording
    }

    public static func hudPhase(
        for state: DictationLifecycleState
    ) -> DictationHUDPhase {
        switch state {
        case .idle:
            return .hidden
        case .requestingPermission, .listening:
            return .listening
        case .processing:
            return .processing
        case .success:
            return .success
        case .failure:
            return .failure
        }
    }
}

public enum AudioLevelPolicy {
    public static func normalizedLevel(meanSquare: Float) -> Double {
        guard meanSquare > 0 else { return 0 }
        let decibels = 10 * log10(Double(meanSquare))
        let noiseFloor = -52.0
        let normalized = (decibels - noiseFloor) / -noiseFloor
        return min(1, max(0, normalized))
    }

    public static func smoothedLevel(
        previous: Double,
        current: Double
    ) -> Double {
        let attack = 0.58
        let release = 0.22
        let weight = current > previous ? attack : release
        return min(1, max(0, previous + (current - previous) * weight))
    }
}

public enum AudioWaveformPolicy {
    public static func barHeights(level: Double) -> [Double] {
        let boundedLevel = min(1, max(0, level))
        let profiles = [0.58, 0.82, 1.0, 0.82, 0.58]
        return profiles.map { profile in
            3 + (17 * boundedLevel * profile)
        }
    }
}
