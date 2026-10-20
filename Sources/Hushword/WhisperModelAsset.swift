import Foundation

package struct WhisperModelAsset: Equatable, Sendable {
    package let fileName: String
    package let downloadURL: URL
    package let expectedByteCount: Int64
    package let sha256: String

    package init(
        fileName: String,
        downloadURL: URL,
        expectedByteCount: Int64,
        sha256: String
    ) {
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.expectedByteCount = expectedByteCount
        self.sha256 = sha256
    }

    package static let largeV3TurboQ5 = WhisperModelAsset(
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        downloadURL: URL(
            string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
        )!,
        expectedByteCount: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    )

    package static func distributionLargeV3TurboQ5(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> WhisperModelAsset {
        let pinnedAsset = largeV3TurboQ5
        guard let configuredURL = infoDictionary[
            "HushwordWhisperModelURL"
        ] as? String,
        let url = URL(string: configuredURL),
        url.scheme?.lowercased() == "https" else {
            return pinnedAsset
        }
        return WhisperModelAsset(
            fileName: pinnedAsset.fileName,
            downloadURL: url,
            expectedByteCount: pinnedAsset.expectedByteCount,
            sha256: pinnedAsset.sha256
        )
    }
}

package enum WhisperModelState: Equatable, Sendable {
    case notInstalled
    case downloading
    case verifying
    case ready
    case failed(String)
}

package enum WhisperModelAvailabilityPolicy {
    package static func shouldAttemptWhisper(
        for state: WhisperModelState
    ) -> Bool {
        state == .ready
    }
}
