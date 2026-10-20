package enum AppleSpeechBackend: Sendable {
    case modernDictation
    case legacy
}

package enum AppleSpeechBackendPolicy {
    package static func preferredBackend(
        osSupportsModernDictation: Bool,
        localeIsSupported: Bool
    ) -> AppleSpeechBackend {
        osSupportsModernDictation && localeIsSupported
            ? .modernDictation
            : .legacy
    }
}
