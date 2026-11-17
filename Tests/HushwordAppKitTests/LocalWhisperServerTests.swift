import HushwordCore
import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    @MainActor
    static func ownsLocalHTTPServerLifecycle() async throws {
        let port = 19_000 + Int(getpid() % 1_000)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        let server = LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "hushword-test-http-server",
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [
                    "-m", "http.server", String(port),
                    "--bind", "127.0.0.1",
                ],
                healthURL: healthURL,
                maximumStartupChecks: 40,
                startupCheckIntervalNanoseconds: 50_000_000
            )
        )

        guard await server.startIfNeeded(),
              await server.isHealthy() else {
            throw TestFailure(description: "managed local HTTP server did not become healthy")
        }

        server.shutdown()
        for _ in 0..<20 where await server.isHealthy() {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard await server.isHealthy() == false else {
            throw TestFailure(description: "managed local HTTP server survived shutdown")
        }
    }

    @MainActor
    static func restartsLocalHTTPServerImmediatelyAfterShutdown() async throws {
        let port = 20_000 + Int(getpid() % 1_000)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        let server = LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "hushword-test-restart-server",
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [
                    "-m", "http.server", String(port),
                    "--bind", "127.0.0.1",
                ],
                healthURL: healthURL,
                maximumStartupChecks: 80,
                startupCheckIntervalNanoseconds: 25_000_000
            )
        )

        guard await server.startIfNeeded() else {
            throw TestFailure(description: "restart test server did not start")
        }
        server.shutdown()
        guard await server.startIfNeeded() else {
            throw TestFailure(description: "server did not restart immediately after shutdown")
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard await server.isHealthy() else {
            throw TestFailure(description: "restarted server disappeared after old cleanup")
        }
        server.shutdown()
    }

    @MainActor
    static func passesRuntimeEnvironmentToLocalHTTPServer() async throws {
        let port = 21_000 + Int(getpid() % 1_000)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        let environmentValue = "hushword-backends-\(UUID().uuidString)"
        let script = """
        import http.server
        import os

        value = os.environ.get("HUSHWORD_RUNTIME_TEST", "")

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = value.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                pass

        http.server.HTTPServer(("127.0.0.1", \(port)), Handler).serve_forever()
        """
        let server = LocalHTTPServerProcess(
            configuration: LocalHTTPServerConfiguration(
                processLabel: "hushword-test-environment-server",
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-c", script],
                environment: ["HUSHWORD_RUNTIME_TEST": environmentValue],
                healthURL: healthURL,
                maximumStartupChecks: 40,
                startupCheckIntervalNanoseconds: 50_000_000
            )
        )

        guard await server.startIfNeeded() else {
            throw TestFailure(description: "environment test server did not start")
        }
        defer { server.shutdown() }

        let (body, _) = try await URLSession.shared.data(from: healthURL)
        guard String(data: body, encoding: .utf8) == environmentValue else {
            throw TestFailure(description: "local server lost its runtime environment")
        }
    }

    @MainActor
    static func keepsWhisperWarmForTwoIdleMinutes() async throws {
        guard WhisperLifecyclePolicy.idleShutdownNanoseconds
            == 120_000_000_000 else {
            throw TestFailure(description: "Whisper idle shutdown is not two minutes")
        }
    }

    @MainActor
    static func releasesWhisperSafelyUnderMemoryPressure() async throws {
        var state = WhisperMemoryPressureState()
        guard state.receivePressure() else {
            throw TestFailure(
                description: "idle Whisper did not release under memory pressure"
            )
        }

        state.beginTranscription()
        guard state.receivePressure() == false,
              state.finishTranscription(),
              state.finishTranscription() == false else {
            throw TestFailure(
                description: "active Whisper was interrupted or deferred release repeated"
            )
        }
    }

    @MainActor
    static func buildsAndCleansFileBackedMultipartUpload() async throws {
        let fileManager = FileManager.default
        let audioURL = fileManager.temporaryDirectory
            .appendingPathComponent("hushword-multipart-test-\(UUID().uuidString).wav")
        let audio = Data([0, 1, 2, 3, 4, 5, 6, 7])
        try audio.write(to: audioURL)
        defer { try? fileManager.removeItem(at: audioURL) }

        let upload = try MultipartUploadFile(
            fields: [
                "language": "zh",
                "beam_size": "1",
                "best_of": "1",
            ],
            audioURL: audioURL
        )
        let bodyURL = upload.bodyURL
        guard fileManager.fileExists(atPath: bodyURL.path),
              bodyURL != audioURL,
              let bodySize = try? fileManager
                .attributesOfItem(atPath: bodyURL.path)[.size] as? NSNumber,
              bodySize.intValue > audio.count else {
            throw TestFailure(description: "multipart upload was not file-backed")
        }

        let body = try Data(contentsOf: bodyURL)
        guard let text = String(data: body, encoding: .isoLatin1),
              text.contains("name=\"language\"\r\n\r\nzh"),
              text.contains("name=\"beam_size\"\r\n\r\n1"),
              text.contains("name=\"best_of\"\r\n\r\n1"),
              text.contains("filename=\"recording.wav\"") else {
            throw TestFailure(description: "multipart upload lost request fields")
        }

        upload.cleanup()
        guard fileManager.fileExists(atPath: bodyURL.path) == false else {
            throw TestFailure(description: "multipart upload file survived cleanup")
        }
    }

    @MainActor
    static func decodesWordConfidenceFromVerboseWhisperJSON() async throws {
        let data = Data(
            """
            {
              "text": "所以我们能发 paper 吗？",
              "segments": [
                {
                  "words": [
                    {"word": "所以", "probability": 0.99},
                    {"word": " paper", "probability": 0.72}
                  ]
                },
                {
                  "words": [
                    {"word": "吗", "probability": 0.98}
                  ]
                }
              ]
            }
            """.utf8
        )
        let candidate = try WhisperServerResponseDecoder.decode(data)
        guard candidate.text == "所以我们能发 paper 吗？",
              candidate.words == [
                  WhisperWordConfidence(text: "所以", probability: 0.99),
                  WhisperWordConfidence(text: " paper", probability: 0.72),
                  WhisperWordConfidence(text: "吗", probability: 0.98),
              ] else {
            throw TestFailure(
                description: "verbose Whisper confidence was lost: \(candidate)"
            )
        }
    }
}
