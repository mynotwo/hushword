import Foundation

package final class MultipartUploadFile {
    package enum UploadError: Error {
        case cannotEncodeText
    }

    package let bodyURL: URL
    package let boundary: String

    private let fileManager: FileManager
    private var needsCleanup = true

    package init(
        fields: [String: String],
        audioURL: URL,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        boundary = "Hushword-\(UUID().uuidString)"
        bodyURL = fileManager.temporaryDirectory
            .appendingPathComponent("hushword-upload-\(UUID().uuidString)")
            .appendingPathExtension("multipart")

        guard fileManager.createFile(atPath: bodyURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let output = try FileHandle(forWritingTo: bodyURL)
            defer { try? output.close() }

            for name in fields.keys.sorted() {
                guard let value = fields[name] else { continue }
                try write(
                    "--\(boundary)\r\n"
                        + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                        + "\(value)\r\n",
                    to: output
                )
            }
            try write(
                "--\(boundary)\r\n"
                    + "Content-Disposition: form-data; name=\"file\"; "
                    + "filename=\"recording.wav\"\r\n"
                    + "Content-Type: audio/wav\r\n\r\n",
                to: output
            )
            try appendFile(at: audioURL, to: output)
            try write("\r\n--\(boundary)--\r\n", to: output)
        } catch {
            cleanup()
            throw error
        }
    }

    deinit {
        cleanup()
    }

    package func cleanup() {
        guard needsCleanup else { return }
        needsCleanup = false
        try? fileManager.removeItem(at: bodyURL)
    }

    private func write(
        _ text: String,
        to output: FileHandle
    ) throws {
        guard let data = text.data(using: .utf8) else {
            throw UploadError.cannotEncodeText
        }
        try output.write(contentsOf: data)
    }

    private func appendFile(
        at sourceURL: URL,
        to output: FileHandle
    ) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }

        while let chunk = try input.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }
}
