import FlowTypeCore
import Foundation

package enum WhisperServerResponseDecoder {
    private struct Response: Decodable {
        struct Segment: Decodable {
            struct Word: Decodable {
                let word: String
                let probability: Double
            }

            let words: [Word]?
        }

        let text: String
        let segments: [Segment]?
    }

    package static func decode(
        _ data: Data
    ) throws -> WhisperTranscriptCandidate {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return WhisperTranscriptCandidate(
            text: response.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            words: response.segments?
                .flatMap { $0.words ?? [] }
                .map {
                    WhisperWordConfidence(
                        text: $0.word,
                        probability: $0.probability
                    )
                } ?? []
        )
    }
}

@MainActor
final class WhisperFinalizer {
    private let fileManager = FileManager.default
    private let port = 18_188
    private var server: LocalHTTPServerProcess?
    private var startupTask: Task<Bool, Never>?
    private var startupGeneration: UInt64 = 0
    private var idleShutdownTask: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0
    private var memoryPressureState = WhisperMemoryPressureState()
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func prewarm() {
        let generation = beginActivity()
        beginServerStartupIfNeeded()
        scheduleIdleShutdown(afterActivityGeneration: generation)
    }

    func finishActivityWithoutTranscription() {
        let generation = beginActivity()
        scheduleIdleShutdown(afterActivityGeneration: generation)
    }

    func transcribe(
        audioURL: URL,
        localeIdentifier: String,
        contextualStrings: [String]
    ) async -> String? {
        let generation = beginActivity()
        memoryPressureState.beginTranscription()
        defer {
            if memoryPressureState.finishTranscription() {
                releaseServer()
            } else {
                scheduleIdleShutdown(afterActivityGeneration: generation)
            }
        }

        guard let modelURL,
              BilingualFinalizationPolicy.shouldRun(
                  executableExists: runtime != nil,
                  modelExists: fileManager.fileExists(atPath: modelURL.path),
                  recordingHasAudio: fileManager.fileExists(atPath: audioURL.path)
              ) else {
            return nil
        }

        if await startServerIfNeeded(),
           let transcript = await transcribeWithServer(
               audioURL: audioURL,
               localeIdentifier: localeIdentifier,
               contextualStrings: contextualStrings
           ) {
            return transcript
        }
        return await transcribeWithCLI(
            audioURL: audioURL,
            modelURL: modelURL,
            localeIdentifier: localeIdentifier,
            contextualStrings: contextualStrings
        )
    }

    func shutdown() {
        activityGeneration &+= 1
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        startupTask?.cancel()
        startupTask = nil
        server?.shutdown()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    @discardableResult
    private func beginActivity() -> UInt64 {
        activityGeneration &+= 1
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        return activityGeneration
    }

    private func beginServerStartupIfNeeded() {
        guard startupTask == nil else { return }
        if server == nil {
            server = makeServer()
        }
        guard let server else { return }

        startupGeneration &+= 1
        let generation = startupGeneration
        let task = Task {
            await server.startIfNeeded()
        }
        startupTask = task
        Task { [weak self] in
            _ = await task.value
            guard let self,
                  self.startupGeneration == generation else {
                return
            }
            self.startupTask = nil
        }
    }

    private func startServerIfNeeded() async -> Bool {
        beginServerStartupIfNeeded()
        guard let startupTask else { return false }
        return await startupTask.value
    }

    private func scheduleIdleShutdown(
        afterActivityGeneration generation: UInt64
    ) {
        guard generation == activityGeneration else { return }
        idleShutdownTask?.cancel()
        idleShutdownTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: WhisperLifecyclePolicy.idleShutdownNanoseconds
            )
            guard !Task.isCancelled,
                  let self,
                  self.activityGeneration == generation else {
                return
            }
            self.releaseServer()
        }
    }

    private func handleMemoryPressure() {
        if memoryPressureState.receivePressure() {
            releaseServer()
        }
    }

    private func releaseServer() {
        activityGeneration &+= 1
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        startupGeneration &+= 1
        startupTask?.cancel()
        startupTask = nil
        server?.shutdown()
    }

    private func transcribeWithServer(
        audioURL: URL,
        localeIdentifier: String,
        contextualStrings: [String]
    ) async -> String? {
        guard let endpoint = URL(
            string: "http://127.0.0.1:\(port)/inference"
        ) else {
            return nil
        }

        guard let primary = await requestCandidate(
            endpoint: endpoint,
            audioURL: audioURL,
            fields: WhisperRequestPolicy.fields(
                localeIdentifier: localeIdentifier,
                contextualStrings: contextualStrings
            )
        ) else {
            return nil
        }
        guard WhisperConfidenceRetryPolicy.shouldRetry(
            words: primary.words
        ), let retry = await requestCandidate(
            endpoint: endpoint,
            audioURL: audioURL,
            fields: WhisperRequestPolicy.retryFields(
                localeIdentifier: localeIdentifier,
                contextualStrings: contextualStrings
            )
        ) else {
            return primary.text.isEmpty ? nil : primary.text
        }

        let selected = WhisperConfidenceRetryPolicy.select(
            primary: primary,
            retry: retry,
            contextualStrings: contextualStrings
        )
        return selected.text.isEmpty ? nil : selected.text
    }

    private func requestCandidate(
        endpoint: URL,
        audioURL: URL,
        fields: [String: String]
    ) async -> WhisperTranscriptCandidate? {
        guard let upload = try? MultipartUploadFile(
            fields: fields,
            audioURL: audioURL
        ) else {
            return nil
        }
        defer { upload.cleanup() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(
            "multipart/form-data; boundary=\(upload.boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        do {
            let (data, response) = try await URLSession.shared.upload(
                for: request,
                fromFile: upload.bodyURL
            )
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            let candidate = try WhisperServerResponseDecoder.decode(data)
            return candidate.text.isEmpty ? nil : candidate
        } catch {
            return nil
        }
    }

    private func transcribeWithCLI(
        audioURL: URL,
        modelURL: URL,
        localeIdentifier: String,
        contextualStrings: [String]
    ) async -> String? {
        guard let runtime,
              let cliExecutableURL = runtime.cliExecutableURL else {
            return nil
        }
        let arguments = WhisperCommandPolicy.arguments(
            modelPath: modelURL.path,
            audioPath: audioURL.path,
            localeIdentifier: localeIdentifier,
            contextualStrings: contextualStrings
        )

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = cliExecutableURL
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(
                runtime.environment
            ) { _, override in
                override
            }
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let output = String(data: outputData, encoding: .utf8) else {
                    return nil
                }
                let transcript = output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return transcript.isEmpty ? nil : transcript
            } catch {
                return nil
            }
        }.value
    }

    private func makeServer() -> LocalHTTPServerProcess? {
        guard let runtime,
              let modelURL,
              let healthURL = URL(
                  string: "http://127.0.0.1:\(port)/health"
              ) else {
            return nil
        }
        return LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "flowtype-whisper-server",
                executableURL: runtime.serverExecutableURL,
                arguments: WhisperServerPolicy.arguments(
                    modelPath: modelURL.path,
                    port: port,
                    contextualStrings: []
                ),
                environment: runtime.environment,
                healthURL: healthURL
            )
        )
    }

    private var runtime: WhisperRuntime? {
        WhisperRuntimeLocator.locate(fileManager: fileManager)
    }

    private var modelURL: URL? {
        WhisperModelInstaller.verifiedModelURL(
            asset: .largeV3TurboQ5,
            modelsDirectory: WhisperModelInstaller.modelsDirectory(
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }
}
