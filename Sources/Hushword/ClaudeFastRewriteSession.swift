import HushwordCore
import Foundation

actor ClaudeFastRewriteSession {
    private struct PendingRequest {
        let id: UUID
        let continuation: CheckedContinuation<String, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let command: AICommand
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = Data()
    private var pendingRequest: PendingRequest?
    private var isPreparing = false
    private var isReady = false
    private var generation: UUID?

    init(homeDirectory: String) {
        command = AICommandBuilder.buildClaudeSession(
            homeDirectory: homeDirectory
        )
    }

    func prepare() async -> Bool {
        if isReady, process?.isRunning == true {
            return true
        }
        guard !isPreparing, pendingRequest == nil else { return false }
        isPreparing = true
        defer { isPreparing = false }

        do {
            try start()
            _ = try await request(
                "Return exactly READY.",
                timeoutNanoseconds: 15_000_000_000,
                requiresReadySession: false
            )
            isReady = true
            return true
        } catch {
            stop()
            return false
        }
    }

    func rewrite(
        prompt: String,
        timeoutNanoseconds: UInt64
    ) async throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: .nanoseconds(Int64(clamping: timeoutNanoseconds))
        )
        while isPreparing, !isReady {
            guard clock.now < deadline else {
                throw AIRewriteService.RewriteError.timedOut
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard isReady, process?.isRunning == true else {
            throw AIRewriteService.RewriteError.fastSessionNotReady
        }
        return try await request(
            prompt,
            timeoutNanoseconds: remainingNanoseconds(
                until: deadline,
                clock: clock
            ),
            requiresReadySession: true
        )
    }

    func shutdown() {
        if let pendingRequest {
            finishRequest(
                pendingRequest.id,
                result: .failure(CancellationError()),
                stopSession: true
            )
        } else {
            stop()
        }
    }

    private func start() throws {
        stop()
        guard FileManager.default.isExecutableFile(
            atPath: command.executable
        ) else {
            throw AIRewriteService.RewriteError.providerUnavailable(
                AIProvider.claude.rawValue.capitalized
            )
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let generation = UUID()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment
            .merging(command.environment) { _, override in override }
        outputPipe.fileHandleForReading.readabilityHandler = {
            [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.receive(data, generation: generation)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.processTerminated(generation: generation)
            }
        }
        try process.run()
        self.generation = generation
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
    }

    private func request(
        _ prompt: String,
        timeoutNanoseconds: UInt64,
        requiresReadySession: Bool
    ) async throws -> String {
        guard process?.isRunning == true,
              !requiresReadySession || isReady else {
            throw AIRewriteService.RewriteError.fastSessionNotReady
        }
        guard pendingRequest == nil else {
            throw AIRewriteService.RewriteError.fastSessionNotReady
        }

        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: timeoutNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    await self?.timeOut(requestID)
                }
                pendingRequest = PendingRequest(
                    id: requestID,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                do {
                    try send(prompt)
                } catch {
                    finishRequest(
                        requestID,
                        result: .failure(error),
                        stopSession: true
                    )
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancel(requestID)
            }
        }
    }

    private func send(_ prompt: String) throws {
        let message: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": prompt,
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try inputPipe?.fileHandleForWriting.write(contentsOf: data)
    }

    private func remainingNanoseconds(
        until deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) throws -> UInt64 {
        let now = clock.now
        guard now < deadline else {
            throw AIRewriteService.RewriteError.timedOut
        }
        let components = now.duration(to: deadline).components
        return UInt64(components.seconds) * 1_000_000_000
            + UInt64(components.attoseconds / 1_000_000_000)
    }

    private func receive(_ data: Data, generation: UUID) {
        guard self.generation == generation else { return }
        guard !data.isEmpty else {
            processTerminated(generation: generation)
            return
        }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            receiveLine(Data(line))
        }
    }

    private func receiveLine(_ data: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              event["type"] as? String == "result",
              let pendingRequest else {
            return
        }
        let result = (event["result"] as? String) ?? ""
        if (event["is_error"] as? Bool) == true || result.isEmpty {
            finishRequest(
                pendingRequest.id,
                result: .failure(
                    AIRewriteService.RewriteError.failed(result)
                )
            )
        } else {
            finishRequest(
                pendingRequest.id,
                result: .success(result)
            )
        }
    }

    private func timeOut(_ requestID: UUID) {
        finishRequest(
            requestID,
            result: .failure(AIRewriteService.RewriteError.timedOut),
            stopSession: true
        )
    }

    private func cancel(_ requestID: UUID) {
        finishRequest(
            requestID,
            result: .failure(CancellationError()),
            stopSession: true
        )
    }

    private func processTerminated(generation: UUID) {
        guard self.generation == generation else { return }
        guard let pendingRequest else {
            stop()
            return
        }
        finishRequest(
            pendingRequest.id,
            result: .failure(
                AIRewriteService.RewriteError.failed(
                    "Fast AI rewrite session stopped."
                )
            ),
            stopSession: true
        )
    }

    private func finishRequest(
        _ requestID: UUID,
        result: Result<String, Error>,
        stopSession: Bool = false
    ) {
        guard let pendingRequest,
              pendingRequest.id == requestID else {
            return
        }
        self.pendingRequest = nil
        pendingRequest.timeoutTask.cancel()
        pendingRequest.continuation.resume(with: result)
        if stopSession {
            stop()
        }
    }

    private func stop() {
        isReady = false
        generation = nil
        outputBuffer.removeAll(keepingCapacity: true)
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.interrupt()
            if process.isRunning {
                process.terminate()
            }
        }
        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }
}
