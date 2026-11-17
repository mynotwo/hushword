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
