import HushwordCore
import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    static func selectsConfiguredAgentForLongPressRewrite() async throws {
        guard AgentProviderSelection.resolve(
            preference: .auto,
            availableProviders: [.claude, .codex, .coco],
            readyProviders: [.codex]
        ) == .codex,
        AgentProviderSelection.resolve(
            preference: .claude,
            availableProviders: [.claude, .codex],
            readyProviders: [.codex]
        ) == .claude,
        AgentProviderSelection.resolve(
            preference: .codex,
            availableProviders: [.claude, .codex],
            readyProviders: [.claude]
        ) == .codex,
        AgentProviderSelection.resolve(
            preference: .coco,
            availableProviders: [.coco],
            readyProviders: []
        ) == .coco,
        AgentProviderSelection.resolve(
            preference: .off,
            availableProviders: [.claude, .codex, .coco],
            readyProviders: [.claude, .codex]
        ) == nil else {
            throw TestFailure(
                description: "Fn long press ignored the configured Agent"
            )
        }
    }

    static func capsLongPressRewriteLatency() async throws {
        guard AgentRewritePolicy.longPressActivationNanoseconds
                + AgentRewritePolicy.longPressTimeoutNanoseconds
                <= 3_000_000_000,
              AgentRewritePolicy.longPressTimeoutNanoseconds
                <= 2_500_000_000 else {
            throw TestFailure(
                description: "Fn long press can keep the user waiting over three seconds"
            )
        }
    }

    static func usesPrewarmedNoThinkingHaikuSession() async throws {
        let command = AICommandBuilder.buildClaudeSession(
            homeDirectory: "/Users/test"
        )
        guard command.executable == "/Users/test/.local/bin/claude",
              command.arguments.contains("--model"),
              command.arguments.contains("haiku"),
              command.arguments.contains("--input-format"),
              command.arguments.contains("stream-json"),
              command.arguments.contains("--include-partial-messages"),
              command.environment["MAX_THINKING_TOKENS"] == "0" else {
            throw TestFailure(
                description: "fast rewrite does not use a reusable no-thinking Haiku session"
            )
        }
    }

    static func reusesPrewarmedCodexAppServerSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-codex-warm-session-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let codexDirectory = directory.appendingPathComponent(
            ".codex",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )
        let authURL = codexDirectory.appendingPathComponent("auth.json")
        try "{}".write(to: authURL, atomically: true, encoding: .utf8)
        let executableURL = binDirectory.appendingPathComponent("codex")
        let logURL = directory.appendingPathComponent("requests.log")
        let codexHomeURL = directory.appendingPathComponent("codex-home.txt")
        try """
        #!/bin/sh
        printf '%s' "$CODEX_HOME" > '\(codexHomeURL.path)'
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          printf '%s\n' "$line" >> '\(logURL.path)'
          if [ "$count" -eq 1 ]; then
            printf '%s\n' '{"id":1,"result":{"userAgent":"fake"}}'
          elif [ "$count" -eq 3 ]; then
            printf '%s\n' '{"id":2,"result":{"thread":{"id":"thread-1"}}}'
          elif [ "$count" -eq 4 ]; then
            printf '%s\n' '{"id":3,"result":{"turn":{"id":"turn-1"}}}'
            printf '%s\n' '{"method":"item/completed","params":{"item":{"type":"agentMessage","id":"message-1","text":"READY","phase":"final_answer"},"threadId":"thread-1","turnId":"turn-1","completedAtMs":1}}'
          elif [ "$count" -eq 5 ]; then
            printf '%s\n' '{"id":4,"result":{"turn":{"id":"turn-2"}}}'
            printf '%s\n' '{"method":"item/completed","params":{"item":{"type":"agentMessage","id":"message-2","text":"Codex 已润色。","phase":"final_answer"},"threadId":"thread-1","turnId":"turn-2","completedAtMs":2}}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        guard await service.prepareFastRewrite(provider: .codex) else {
            let requests = (try? String(
                contentsOf: logURL,
                encoding: .utf8
            )) ?? "no requests"
            throw TestFailure(
                description: "Codex app-server did not warm up: \(requests)"
            )
        }
        let rewritten = try await service.rewriteFast(
            "请润色。",
            with: .codex,
            mode: .natural,
            timeoutNanoseconds: 500_000_000
        )
        let requests = try String(contentsOf: logURL, encoding: .utf8)
        let isolatedHomePath = try String(
            contentsOf: codexHomeURL,
            encoding: .utf8
        )
        let isolatedHome = URL(fileURLWithPath: isolatedHomePath)
        let isolatedConfig = try String(
            contentsOf: isolatedHome.appendingPathComponent("config.toml"),
            encoding: .utf8
        )
        let isolatedAuth = isolatedHome.appendingPathComponent("auth.json")
        guard isolatedHomePath.contains("hushword-codex-"),
              isolatedHomePath != codexDirectory.path,
              FileManager.default.fileExists(atPath: isolatedAuth.path),
              isolatedConfig.contains("model = \"gpt-5.5\""),
              isolatedConfig.contains("service_tier = \"priority\""),
              requests.contains("\"model\":\"gpt-5.5\""),
              requests.contains("\"serviceTier\":\"priority\"") else {
            throw TestFailure(
                description: "Codex fast session still loads the global Agent environment"
            )
        }
        await service.shutdownFastRewrite()
        guard rewritten == "Codex 已润色。",
              !FileManager.default.fileExists(
                atPath: isolatedHome.path
              ) else {
            throw TestFailure(
                description: "Codex did not reuse and clean its isolated app-server: \(rewritten)"
            )
        }
    }

    static func meetsLiveCodexLongPressDeadline() async throws {
        guard ProcessInfo.processInfo.environment[
            "HUSHWORD_LIVE_CODEX_TEST"
        ] == "1" else {
            return
        }

        let service = AIRewriteService()
        guard await service.prepareFastRewrite(provider: .codex) else {
            throw TestFailure(
                description: "live Codex app-server did not warm up"
            )
        }
        do {
            let rewritten = try await service.rewriteFast(
                "嗯我觉得这个其实可以先做然后我们明天再看一下效果",
                with: .codex,
                mode: .natural,
                timeoutNanoseconds:
                    AgentRewritePolicy.longPressTimeoutNanoseconds
            )
            await service.shutdownFastRewrite()
            guard rewritten.contains("先做"),
                  rewritten.contains("明天") else {
                throw TestFailure(
                    description: "live Codex changed the original meaning: \(rewritten)"
                )
            }
        } catch {
            await service.shutdownFastRewrite()
            throw error
        }
    }

    static func requiresReadySessionForFastRewrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-warm-session-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            printf '%s\n' '{"type":"result","result":"预热后的结果。"}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        do {
            _ = try await service.rewriteFast(
                "请润色。",
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "fast rewrite started a cold session on demand"
            )
        } catch AIRewriteService.RewriteError.fastSessionNotReady {
        }

        guard await service.prepareFastRewrite() else {
            throw TestFailure(description: "fast rewrite session did not warm up")
        }
        let rewritten = try await service.rewriteFast(
            "请润色。",
            mode: .natural,
            timeoutNanoseconds: 100_000_000
        )
        await service.shutdownFastRewrite()
        guard rewritten == "预热后的结果。" else {
            throw TestFailure(
                description: "fast rewrite did not reuse its warm process: \(rewritten)"
            )
        }
    }

    static func waitsForInFlightFastSessionPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-preparation-race-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let markerURL = directory.appendingPathComponent("warming")
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            touch '\(markerURL.path)'
            sleep 0.15
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            printf '%s\n' '{"type":"result","result":"预热竞态已处理。"}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        let preparation = Task {
            await service.prepareFastRewrite()
        }
        await Task.yield()
        for _ in 0..<400 where !FileManager.default.fileExists(
            atPath: markerURL.path
        ) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            throw TestFailure(description: "fast rewrite preparation never started")
        }

        let rewritten = try await service.rewriteFast(
            "请润色。",
            mode: .natural,
            timeoutNanoseconds: 500_000_000
        )
        let prepared = await preparation.value
        await service.shutdownFastRewrite()
        guard prepared, rewritten == "预热竞态已处理。" else {
            throw TestFailure(
                description: "fast rewrite rejected an in-flight warm session"
            )
        }
    }

    static func includesFastSessionPreparationInRewriteDeadline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-preparation-deadline-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let markerURL = directory.appendingPathComponent("warming")
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            touch '\(markerURL.path)'
            sleep 1
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            printf '%s\n' '{"type":"result","result":"不应等到这个结果。"}'
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        let preparation = Task {
            await service.prepareFastRewrite()
        }
        await Task.yield()
        for _ in 0..<400 where !FileManager.default.fileExists(
            atPath: markerURL.path
        ) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            throw TestFailure(description: "fast rewrite preparation never started")
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await service.rewriteFast(
                "请润色。",
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "fast rewrite ignored its preparation deadline"
            )
        } catch AIRewriteService.RewriteError.timedOut {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 1 else {
                throw TestFailure(
                    description: "fast rewrite waited beyond its total deadline"
                )
            }
        }
        preparation.cancel()
        await service.shutdownFastRewrite()
    }

    static func recoversFastSessionAfterTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-fast-timeout-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          if [ "$count" -eq 1 ]; then
            printf '%s\n' '{"type":"result","result":"READY"}'
          else
            sleep 30
          fi
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(homeDirectory: directory.path)
        guard await service.prepareFastRewrite() else {
            throw TestFailure(description: "fast rewrite session did not warm up")
        }
        do {
            _ = try await service.rewriteFast(
                "请润色。",
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "slow fast rewrite unexpectedly completed"
            )
        } catch AIRewriteService.RewriteError.timedOut {
        }
        guard await service.prepareFastRewrite() else {
            throw TestFailure(
                description: "fast rewrite session did not recover after timeout"
            )
        }
        await service.shutdownFastRewrite()
    }

    static func appliesPerRequestAIRewriteTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-request-timeout-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        sleep 30
        printf 'late result'
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(
            homeDirectory: directory.path,
            timeoutNanoseconds: 30_000_000_000
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await service.rewrite(
                "Please rewrite this.",
                with: .claude,
                mode: .natural,
                timeoutNanoseconds: 100_000_000
            )
            throw TestFailure(
                description: "slow AI rewrite unexpectedly completed"
            )
        } catch AIRewriteService.RewriteError.timedOut {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 2 else {
                throw TestFailure(
                    description: "per-request AI rewrite timeout was ignored"
                )
            }
        }
    }

    @MainActor
    static func closesAIRewriteProcessStandardInput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-stdin-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")

        let status = try await AIProcessRunner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "if read line; then exit 9; else printf eof; fi",
            ],
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            timeoutNanoseconds: 2_000_000_000
        )

        guard status == 0,
              try String(contentsOf: stdoutURL, encoding: .utf8) == "eof" else {
            throw TestFailure(
                description: "AI rewrite process inherited an open standard input"
            )
        }
    }

    @MainActor
    static func cancelsAIRewriteProcessPromptly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-cancel-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await AIProcessRunner.run(
                executable: "/bin/sleep",
                arguments: ["30"],
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                timeoutNanoseconds: 30_000_000_000
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(
                description: "cancelled AI rewrite unexpectedly completed"
            )
        } catch is CancellationError {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 2 else {
                throw TestFailure(
                    description: "cancelled AI rewrite kept running"
                )
            }
        }
    }

    @MainActor
    static func propagatesAIRewriteCancellationToItsProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-ai-service-cancel-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".local/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("claude")
        try """
        #!/bin/sh
        sleep 30
        printf 'late result'
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let service = AIRewriteService(
            homeDirectory: directory.path,
            timeoutNanoseconds: 30_000_000_000
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await service.rewrite(
                "Please rewrite this.",
                with: .claude,
                mode: .natural
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(
                description: "cancelled AI rewrite unexpectedly completed"
            )
        } catch is CancellationError {
            let elapsed = startedAt.duration(to: clock.now).components
            guard elapsed.seconds < 2 else {
                throw TestFailure(
                    description: "AI rewrite cancellation did not reach its process"
                )
            }
        }
    }
}
