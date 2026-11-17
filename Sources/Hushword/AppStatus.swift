import HushwordCore

package enum AppStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case processing
    case success
    case copied(String)
    case error(String)

    package var lifecycleState: DictationLifecycleState {
        switch self {
        case .idle:
            return .idle
        case .requestingPermission:
            return .requestingPermission
        case .listening:
            return .listening
        case .processing:
            return .processing
        case .success, .copied:
            return .success
        case .error:
            return .failure
        }
    }

    package var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .requestingPermission:
            return "Requesting permission…"
        case .listening:
            return "Listening…"
        case .processing:
            return "Transcribing…"
        case .success:
            return "Inserted"
        case .copied(let message), .error(let message):
            return message
        }
    }
}
