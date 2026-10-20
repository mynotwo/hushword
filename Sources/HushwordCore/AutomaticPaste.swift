public struct TargetApplicationSelector: Sendable {
    private let ownProcessIdentifier: Int32
    private var isSelectionLocked = false

    public private(set) var selectedProcessIdentifier: Int32?

    public init(ownProcessIdentifier: Int32) {
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    @discardableResult
    public mutating func observe(
        processIdentifier: Int32,
        isRegularApplication: Bool,
        isTerminated: Bool
    ) -> Bool {
        guard !isSelectionLocked,
              processIdentifier != ownProcessIdentifier,
              isRegularApplication,
              !isTerminated else {
            return false
        }

        selectedProcessIdentifier = processIdentifier
        return true
    }

    public mutating func lockSelection() {
        isSelectionLocked = true
    }

    public mutating func unlockSelection() {
        isSelectionLocked = false
    }
}

public enum PasteActivationDecision: Equatable, Sendable {
    case retry
    case paste
    case giveUp
}

public struct PasteActivationState: Sendable {
    private let maximumChecks: Int
    private var checks = 0

    public init(maximumChecks: Int) {
        self.maximumChecks = max(1, maximumChecks)
    }

    public mutating func next(targetIsActive: Bool) -> PasteActivationDecision {
        if targetIsActive {
            return .paste
        }

        checks += 1
        return checks >= maximumChecks ? .giveUp : .retry
    }
}

public enum AccessibilityPromptTrigger: Sendable {
    case automatic
    case userInitiated
}

public enum AutomaticPastePermissionPolicy {
    public static func shouldRequest(for trigger: AccessibilityPromptTrigger) -> Bool {
        trigger == .userInitiated
    }
}
