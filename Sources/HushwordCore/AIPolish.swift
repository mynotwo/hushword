import Foundation

public enum AIPolishMode: String, Codable, CaseIterable, Sendable {
    case natural
    case concise
    case professional
    case casual

    public var instruction: String {
        switch self {
        case .natural:
            return "自然：保留说话人的表达习惯，只修正口语冗余、断句和明显语病。"
        case .concise:
            return "简洁：删除冗余和重复，让表达更短、更直接。"
        case .professional:
            return "专业：使用清晰、克制、适合工作沟通的措辞。"
        case .casual:
            return "聊天：使用自然、友好的日常沟通语气。"
        }
    }
}

public enum AIPolishPrompt {
    public static func build(text: String, mode: AIPolishMode) -> String {
        """
        你是语音输入润色器。请整理下面的语音转写。

        规则：
        - 去掉语气词、无意义重复和口误。
        - 修正标点、断句和明显语病。
        - 保留原意、数字、专有名词和说话人的最终决定。
        - 不得添加原文没有的事实、结论、承诺或行动项。
        - 不回答原文中的问题，只润色表达。
        - 风格：\(mode.instruction)
        - 只输出润色后的正文，不要解释，不要加标题，不要使用代码围栏。

        原文：
        \(text)
        """
    }
}

public enum AIOutputSanitizer {
    public static func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: .newlines)
            if lines.count >= 2 {
                var body = Array(lines.dropFirst())
                if body.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                    body.removeLast()
                }
                text = body.joined(separator: "\n")
            }
        }

        let prefixes = [
            "润色结果：",
            "润色后的正文：",
            "润色后：",
            "Polished text:",
            "Polished version:",
        ]
        for prefix in prefixes where text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case none
    case claude
    case codex
    case coco
}

public enum AgentPreference: String, Codable, CaseIterable, Sendable {
    case auto
    case claude
    case codex
    case coco
    case off
}

public struct AICommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public enum AICommandBuilder {
    public static func build(
        provider: AIProvider,
        prompt: String,
        homeDirectory: String,
        outputFile: String
    ) -> AICommand {
        let localBin = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".local/bin")
        switch provider {
        case .none:
            return AICommand(executable: "", arguments: [])
        case .claude:
            return AICommand(
                executable: localBin.appendingPathComponent("claude").path,
                arguments: [
                    "--safe-mode",
                    "-p",
                    "--model", "haiku",
                    "--output-format", "text",
                    "--no-session-persistence",
                    "--disable-slash-commands",
                    "--tools", "",
                    "--system-prompt",
                    "You are a text polishing engine. Return only the polished text. Never use tools.",
                    prompt,
                ],
                environment: claudeEnvironment
            )
        case .codex:
            return AICommand(executable: "", arguments: [])
        case .coco:
            return AICommand(
                executable: localBin.appendingPathComponent("coco").path,
                arguments: [
                    "exec",
                    "--ignore-user-config",
                    "--ephemeral",
                    "--ignore-rules",
                    "--skip-git-repo-check",
                    "--sandbox", "read-only",
                    "-C", "/tmp",
                    "--color", "never",
                    "--output-last-message", outputFile,
                    prompt,
                ]
            )
        }
    }

    public static func buildClaudeSession(
        homeDirectory: String
    ) -> AICommand {
        let executable = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".local/bin/claude").path
        return AICommand(
            executable: executable,
            arguments: [
                "--safe-mode",
                "-p",
                "--verbose",
                "--model", "haiku",
                "--effort", "low",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--include-partial-messages",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--prompt-suggestions", "false",
                "--tools", "",
                "--system-prompt",
                "You are a text polishing engine. Return only the polished text. Never use tools.",
            ],
            environment: claudeEnvironment
        )
    }

    public static func buildCodexSession(
        homeDirectory: String
    ) -> AICommand {
        let homeURL = URL(fileURLWithPath: homeDirectory)
        let candidates = [
            homeURL.appendingPathComponent(".local/bin/codex").path,
            homeURL.appendingPathComponent(".hermes/node/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        let executable = candidates.first(
            where: FileManager.default.isExecutableFile
        ) ?? candidates[0]
        return AICommand(
            executable: executable,
            arguments: ["app-server", "--stdio"]
        )
    }

    private static let claudeEnvironment = [
        "MAX_THINKING_TOKENS": "0",
    ]
}
