public enum FunctionKeyPressAction: Equatable, Sendable {
    case none
    case startedPress
    case shortPress
    case longPress
}

public struct FunctionKeyClickState: Sendable {
    private var isPressed = false
    private var didLongPress = false

    public init() {}

    public mutating func reset() {
        isPressed = false
        didLongPress = false
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
            didLongPress = false
            return .startedPress
        }

        guard isPressed else { return .none }
        isPressed = false
        if didLongPress {
            didLongPress = false
            return .none
        }
        return .shortPress
    }

    public mutating func consumeLongPress() -> FunctionKeyPressAction {
        guard isPressed, !didLongPress else { return .none }
        didLongPress = true
        return .longPress
    }

    public mutating func cancelLongPress() {
        guard isPressed else { return }
        didLongPress = false
    }
}
