import Foundation

package enum AIProcessRunner {
    package static func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        stdoutURL: URL,
        stderrURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> Int32 {
        FileManager.default.createFile(
            atPath: stdoutURL.path,
            contents: nil
        )
        FileManager.default.createFile(
            atPath: stderrURL.path,
            contents: nil
        )
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = ProcessInfo.processInfo.environment
            .merging(environment) { _, override in override }
        try process.run()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: .nanoseconds(Int64(clamping: timeoutNanoseconds))
        )
        while process.isRunning {
            if Task.isCancelled {
                stop(process)
                throw CancellationError()
            }
            if clock.now >= deadline {
                stop(process)
                throw AIRewriteService.RewriteError.timedOut
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return process.terminationStatus
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.interrupt()
        if process.isRunning {
            process.terminate()
        }
    }
}
