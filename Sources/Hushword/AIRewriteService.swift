import HushwordCore
import Foundation

package enum AgentRewritePolicy {
    package static let longPressActivationNanoseconds: UInt64 = 500_000_000
    package static let longPressTimeoutNanoseconds: UInt64 = 2_000_000_000
}

package enum AgentProviderSelection {
    package static func resolve(
        preference: AgentPreference,
        availableProviders: Set<AIProvider>,
        readyProviders: Set<AIProvider>
    ) -> AIProvider? {
        switch preference {
        case .auto:
            return [.claude, .codex]
                .first(where: readyProviders.contains)
                ?? [.claude, .codex, .coco]
                    .first(where: availableProviders.contains)
        case .claude:
            return availableProviders.contains(.claude) ? .claude : nil
        case .codex:
            return availableProviders.contains(.codex) ? .codex : nil
        case .coco:
            return availableProviders.contains(.coco) ? .coco : nil
        case .off:
            return nil
        }
    }
}

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

private actor ClaudeFastRewriteSession {
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

private actor CodexFastRewriteSession {
    private static let model = "gpt-5.5"
    private static let serviceTier = "priority"

    private struct PendingRPC {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeoutTask: Task<Void, Never>
    }

    private struct PendingTurn {
        let requestID: Int
        var turnID: String?
        let continuation: CheckedContinuation<String, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let command: AICommand
    private let sourceCodexHome: URL
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var isolatedCodexHome: URL?
    private var outputBuffer = Data()
    private var pendingRPCs: [Int: PendingRPC] = [:]
    private var pendingTurn: PendingTurn?
    private var nextRequestID = 1
    private var threadID: String?
    private var isPreparing = false
    private var isReady = false
    private var generation: UUID?

    init(homeDirectory: String) {
        command = AICommandBuilder.buildCodexSession(
            homeDirectory: homeDirectory
        )
        sourceCodexHome = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".codex", isDirectory: true)
    }

    func prepare() async -> Bool {
        if isReady, process?.isRunning == true {
            return true
        }
        guard !isPreparing,
              pendingRPCs.isEmpty,
              pendingTurn == nil else {
            return false
        }
        isPreparing = true
        defer { isPreparing = false }

        do {
            try start()
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "hushword",
                        "title": "Hushword",
                        "version": "1.0",
                    ],
                    "capabilities": [
                        "experimentalApi": false,
                    ],
                ],
                timeoutNanoseconds: 15_000_000_000
            )
            try send(method: "initialized")
            let response = try await request(
                method: "thread/start",
                params: [
                    "ephemeral": true,
                    "model": Self.model,
                    "serviceTier": Self.serviceTier,
                    "cwd": "/tmp",
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "baseInstructions":
                        "You are a fast text polishing engine. Return only the polished text. Never explain, answer questions, use tools, browse, or run commands.",
                    "developerInstructions":
                        "Preserve meaning, numbers, names, and decisions. Fix only transcription errors, punctuation, sentence boundaries, repetition, and obvious grammar. Output only the final text.",
                ],
                timeoutNanoseconds: 15_000_000_000
            )
            guard let result = response["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let threadID = thread["id"] as? String else {
                throw AIRewriteService.RewriteError.failed(
                    "Codex did not create a rewrite session."
                )
            }
            self.threadID = threadID
            _ = try await turn(
                "Return exactly READY.",
                timeoutNanoseconds: 15_000_000_000
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
        guard isReady,
              process?.isRunning == true,
              threadID != nil else {
            throw AIRewriteService.RewriteError.fastSessionNotReady
        }
        return try await turn(
            prompt,
            timeoutNanoseconds: remainingNanoseconds(
                until: deadline,
                clock: clock
            )
        )
    }

    func shutdown() {
        stop()
    }

    private func start() throws {
        stop()
        guard FileManager.default.isExecutableFile(
            atPath: command.executable
        ) else {
            throw AIRewriteService.RewriteError.providerUnavailable(
                AIProvider.codex.rawValue.capitalized
            )
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let generation = UUID()
        let isolatedCodexHome = try makeIsolatedCodexHome()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment
            .merging([
                "CODEX_HOME": isolatedCodexHome.path,
            ]) { _, override in override }
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
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: isolatedCodexHome)
            throw error
        }
        self.generation = generation
        self.isolatedCodexHome = isolatedCodexHome
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
    }

    private func request(
        method: String,
        params: [String: Any],
        timeoutNanoseconds: UInt64
    ) async throws -> [String: Any] {
        guard process?.isRunning == true else {
            throw AIRewriteService.RewriteError.fastSessionNotReady
        }
        let requestID = consumeRequestID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: timeoutNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    await self?.timeOutRPC(requestID)
                }
                pendingRPCs[requestID] = PendingRPC(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                do {
                    try send(
                        id: requestID,
                        method: method,
                        params: params
                    )
                } catch {
                    finishRPC(
                        requestID,
                        result: .failure(error)
                    )
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelRPC(requestID)
            }
        }
    }

    private func turn(
        _ prompt: String,
        timeoutNanoseconds: UInt64
    ) async throws -> String {
        guard process?.isRunning == true,
              let threadID,
              pendingTurn == nil else {
            throw AIRewriteService.RewriteError.fastSessionNotReady
        }
        let requestID = consumeRequestID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: timeoutNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    await self?.timeOutTurn(requestID)
                }
                pendingTurn = PendingTurn(
                    requestID: requestID,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                do {
                    try send(
                        id: requestID,
                        method: "turn/start",
                        params: [
                            "threadId": threadID,
                            "input": [
                                [
                                    "type": "text",
                                    "text": prompt,
                                ],
                            ],
                            "model": Self.model,
                            "serviceTier": Self.serviceTier,
                            "effort": "low",
                            "summary": "none",
                        ]
                    )
                } catch {
                    finishTurn(
                        requestID,
                        result: .failure(error)
                    )
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelTurn(requestID)
            }
        }
    }

    private func send(
        id: Int? = nil,
        method: String,
        params: [String: Any]? = nil
    ) throws {
        var message: [String: Any] = ["method": method]
        if let id {
            message["id"] = id
        }
        if let params {
            message["params"] = params
        }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try inputPipe?.fileHandleForWriting.write(contentsOf: data)
    }

    private func consumeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func makeIsolatedCodexHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-codex-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let sourceAuth = sourceCodexHome.appendingPathComponent(
                "auth.json"
            )
            if FileManager.default.fileExists(atPath: sourceAuth.path) {
                try FileManager.default.copyItem(
                    at: sourceAuth,
                    to: directory.appendingPathComponent("auth.json")
                )
            }
            try Self.isolatedConfig.write(
                to: directory.appendingPathComponent("config.toml"),
                atomically: true,
                encoding: .utf8
            )
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static let isolatedConfig = """
    approval_policy = "never"
    sandbox_mode = "read-only"
    model = "\(model)"
    model_reasoning_effort = "low"
    model_reasoning_summary = "none"
    service_tier = "\(serviceTier)"
    web_search = "disabled"

    [features]
    apps = false
    browser_use = false
    computer_use = false
    goals = false
    hooks = false
    image_generation = false
    multi_agent = false
    plugins = false
    shell_tool = false
    unified_exec = false
    """

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
        guard let message = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return
        }
        if let requestID = message["id"] as? Int {
            if pendingRPCs[requestID] != nil {
                if let error = message["error"] {
                    finishRPC(
                        requestID,
                        result: .failure(
                            AIRewriteService.RewriteError.failed(
                                String(describing: error)
                            )
                        )
                    )
                } else {
                    finishRPC(
                        requestID,
                        result: .success(message)
                    )
                }
                return
            }
            if var pendingTurn,
               pendingTurn.requestID == requestID {
                if let error = message["error"] {
                    finishTurn(
                        requestID,
                        result: .failure(
                            AIRewriteService.RewriteError.failed(
                                String(describing: error)
                            )
                        )
                    )
                    return
                }
                if let result = message["result"] as? [String: Any],
                   let turn = result["turn"] as? [String: Any],
                   let turnID = turn["id"] as? String {
                    pendingTurn.turnID = turnID
                    self.pendingTurn = pendingTurn
                }
                return
            }
        }

        guard message["method"] as? String == "item/completed",
              let params = message["params"] as? [String: Any],
              let item = params["item"] as? [String: Any],
              item["type"] as? String == "agentMessage",
              let turnID = params["turnId"] as? String,
              let pendingTurn,
              pendingTurn.turnID == turnID else {
            return
        }
        let text = (item["text"] as? String) ?? ""
        guard !text.isEmpty else {
            finishTurn(
                pendingTurn.requestID,
                result: .failure(AIRewriteService.RewriteError.emptyOutput)
            )
            return
        }
        finishTurn(
            pendingTurn.requestID,
            result: .success(text)
        )
    }

    private func timeOutRPC(_ requestID: Int) {
        finishRPC(
            requestID,
            result: .failure(AIRewriteService.RewriteError.timedOut),
            stopSession: true
        )
    }

    private func cancelRPC(_ requestID: Int) {
        finishRPC(
            requestID,
            result: .failure(CancellationError()),
            stopSession: true
        )
    }

    private func timeOutTurn(_ requestID: Int) {
        finishTurn(
            requestID,
            result: .failure(AIRewriteService.RewriteError.timedOut),
            stopSession: true
        )
    }

    private func cancelTurn(_ requestID: Int) {
        finishTurn(
            requestID,
            result: .failure(CancellationError()),
            stopSession: true
        )
    }

    private func processTerminated(generation: UUID) {
        guard self.generation == generation else { return }
        failPendingRequests(
            with: AIRewriteService.RewriteError.failed(
                "Fast Codex rewrite session stopped."
            )
        )
        stop()
    }

    private func finishRPC(
        _ requestID: Int,
        result: Result<[String: Any], Error>,
        stopSession: Bool = false
    ) {
        guard let request = pendingRPCs.removeValue(
            forKey: requestID
        ) else {
            return
        }
        request.timeoutTask.cancel()
        request.continuation.resume(with: result)
        if stopSession {
            stop()
        }
    }

    private func finishTurn(
        _ requestID: Int,
        result: Result<String, Error>,
        stopSession: Bool = false
    ) {
        guard let pendingTurn,
              pendingTurn.requestID == requestID else {
            return
        }
        self.pendingTurn = nil
        pendingTurn.timeoutTask.cancel()
        pendingTurn.continuation.resume(with: result)
        if stopSession {
            stop()
        }
    }

    private func failPendingRequests(with error: Error) {
        let requests = pendingRPCs
        pendingRPCs.removeAll()
        for request in requests.values {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
        if let pendingTurn {
            self.pendingTurn = nil
            pendingTurn.timeoutTask.cancel()
            pendingTurn.continuation.resume(throwing: error)
        }
    }

    private func stop() {
        isReady = false
        threadID = nil
        generation = nil
        outputBuffer.removeAll(keepingCapacity: true)
        failPendingRequests(with: CancellationError())
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
        if let isolatedCodexHome {
            try? FileManager.default.removeItem(at: isolatedCodexHome)
            self.isolatedCodexHome = nil
        }
    }
}

package struct AIRewriteService {
    private let homeDirectory: String
    private let timeoutNanoseconds: UInt64
    private let claudeSession: ClaudeFastRewriteSession
    private let codexSession: CodexFastRewriteSession

    package init(
        homeDirectory: String = FileManager.default
            .homeDirectoryForCurrentUser.path,
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        self.homeDirectory = homeDirectory
        self.timeoutNanoseconds = timeoutNanoseconds
        claudeSession = ClaudeFastRewriteSession(
            homeDirectory: homeDirectory
        )
        codexSession = CodexFastRewriteSession(
            homeDirectory: homeDirectory
        )
    }

    package enum RewriteError: LocalizedError {
        case providerUnavailable(String)
        case fastSessionNotReady
        case timedOut
        case failed(String)
        case emptyOutput

        package var errorDescription: String? {
            switch self {
            case .providerUnavailable(let provider):
                return "\(provider) is not installed."
            case .fastSessionNotReady:
                return "Fast rewrite is warming up. Try again."
            case .timedOut:
                return "Rewrite took too long. Original text kept."
            case .failed(let message):
                return message.isEmpty ? "AI rewrite failed." : message
            case .emptyOutput:
                return "AI returned an empty result."
            }
        }
    }

    package func prepareFastRewrite(
        provider: AIProvider = .claude
    ) async -> Bool {
        switch provider {
        case .claude:
            return await claudeSession.prepare()
        case .codex:
            return await codexSession.prepare()
        case .none, .coco:
            return false
        }
    }

    package func availableProviders() -> Set<AIProvider> {
        let providers: [AIProvider] = [.claude, .codex, .coco]
        return Set(providers.filter { provider in
            let command: AICommand
            switch provider {
            case .claude:
                command = AICommandBuilder.buildClaudeSession(
                    homeDirectory: homeDirectory
                )
            case .codex:
                command = AICommandBuilder.buildCodexSession(
                    homeDirectory: homeDirectory
                )
            case .coco:
                command = AICommandBuilder.build(
                    provider: .coco,
                    prompt: "",
                    homeDirectory: homeDirectory,
                    outputFile: "/tmp/hushword-provider-check"
                )
            case .none:
                return false
            }
            return FileManager.default.isExecutableFile(
                atPath: command.executable
            )
        })
    }

    package func rewriteFast(
        _ text: String,
        with provider: AIProvider = .claude,
        mode: AIPolishMode,
        timeoutNanoseconds: UInt64
    ) async throws -> String {
        let prompt = AIPolishPrompt.build(text: text, mode: mode)
        let raw: String
        switch provider {
        case .claude:
            raw = try await claudeSession.rewrite(
                prompt: prompt,
                timeoutNanoseconds: timeoutNanoseconds
            )
        case .codex:
            raw = try await codexSession.rewrite(
                prompt: prompt,
                timeoutNanoseconds: timeoutNanoseconds
            )
        case .none, .coco:
            throw RewriteError.fastSessionNotReady
        }
        let sanitized = AIOutputSanitizer.sanitize(raw)
        guard !sanitized.isEmpty else {
            throw RewriteError.emptyOutput
        }
        return sanitized
    }

    package func shutdownFastRewrite() async {
        await claudeSession.shutdown()
        await codexSession.shutdown()
    }

    package func rewrite(
        _ text: String,
        with provider: AIProvider,
        mode: AIPolishMode,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> String {
        let prompt = AIPolishPrompt.build(text: text, mode: mode)
        let token = UUID().uuidString
        let resultURL = URL(fileURLWithPath: "/tmp/hushword-ai-\(token).txt")
        let stdoutURL = URL(fileURLWithPath: "/tmp/hushword-ai-\(token).stdout")
        let stderrURL = URL(fileURLWithPath: "/tmp/hushword-ai-\(token).stderr")
        let command = AICommandBuilder.build(
            provider: provider,
            prompt: prompt,
            homeDirectory: homeDirectory,
            outputFile: resultURL.path
        )

        guard !command.executable.isEmpty,
              FileManager.default.isExecutableFile(atPath: command.executable) else {
            throw RewriteError.providerUnavailable(provider.rawValue.capitalized)
        }

        defer {
            for url in [resultURL, stdoutURL, stderrURL] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let terminationStatus = try await AIProcessRunner.run(
            executable: command.executable,
            arguments: command.arguments,
            environment: command.environment,
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            timeoutNanoseconds: timeoutNanoseconds ?? self.timeoutNanoseconds
        )
        guard terminationStatus == 0 else {
            let message = (try? String(contentsOf: stderrURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RewriteError.failed(message)
        }

        let outputURL = provider == .coco ? resultURL : stdoutURL
        let raw = try String(contentsOf: outputURL, encoding: .utf8)
        let sanitized = AIOutputSanitizer.sanitize(raw)
        guard !sanitized.isEmpty else {
            throw RewriteError.emptyOutput
        }
        return sanitized
    }
}
