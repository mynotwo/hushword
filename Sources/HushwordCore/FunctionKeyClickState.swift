public enum FunctionKeyPressAction: Equatable, Sendable {
    case none
    case startedPress
    case shortPress
}

/// Turns raw `Fn` flag changes into taps. A tap is a press and release of
/// `Fn` alone; chords with other modifiers are ignored.
public struct FunctionKeyClickState: Sendable {
    private var isPressed = false

    public init() {}

    public mutating func reset() {
        isPressed = false
    }

    public mutating func consume(
        functionPressed: Bool,
        hasOtherModifiers: Bool
    ) -> FunctionKeyPressAction {
        if functionPressed {
            guard !hasOtherModifiers, !isPressed else {
                return .none
            }
            isPressed = true
            return .startedPress
        }

        guard isPressed else { return .none }
        isPressed = false
        return .shortPress
    }
}
