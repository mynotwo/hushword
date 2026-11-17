import HushwordCore
import Foundation

let aiPolishTests: [(String, () throws -> Void)] = [
    ("builds a constrained concise polish prompt", {
        let prompt = AIPolishPrompt.build(
            text: "嗯这个事情我们明天再说",
            mode: .concise
        )
        guard prompt.contains("不得添加原文没有的事实"),
              prompt.contains("只输出润色后的正文"),
              prompt.contains("简洁") else {
            throw TestFailure(description: "prompt is missing safety or mode instructions: \(prompt)")
        }
    }),
    ("sanitizes fenced AI output", {
        try expectEqual(
            AIOutputSanitizer.sanitize("```text\n润色后的正文。\n```"),
            "润色后的正文。",
            "sanitizes fenced AI output"
        )
    }),
    ("sanitizes explanatory AI prefix", {
        try expectEqual(
            AIOutputSanitizer.sanitize("润色结果：\n这件事明天下午再讨论。"),
            "这件事明天下午再讨论。",
            "sanitizes explanatory AI prefix"
        )
    }),
]

let aiCommandTests: [(String, () throws -> Void)] = [
    ("builds a tool-free Claude command", {
        let command = AICommandBuilder.build(
            provider: .claude,
            prompt: "polish me",
            homeDirectory: "/Users/test",
            outputFile: "/tmp/output.txt"
        )
        guard command.executable == "/Users/test/.local/bin/claude",
              command.arguments.contains("--safe-mode"),
              command.arguments.contains("--no-session-persistence"),
              command.arguments.contains("--disable-slash-commands"),
              command.arguments.contains("--tools"),
              command.arguments.contains("") else {
            throw TestFailure(description: "unsafe Claude command: \(command)")
        }
    }),
    ("builds a persistent Codex app-server command", {
        let command = AICommandBuilder.buildCodexSession(
            homeDirectory: "/Users/test"
        )
        guard command.executable == "/Users/test/.local/bin/codex",
              command.arguments == ["app-server", "--stdio"],
              !command.arguments.contains("exec") else {
            throw TestFailure(
                description: "Codex rewrite does not use app-server: \(command)"
            )
        }
    }),
    ("finds a Hermes-installed Codex executable", {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "hushword-codex-location-\(UUID().uuidString)",
                isDirectory: true
            )
        let binDirectory = directory.appendingPathComponent(
            ".hermes/node/bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableURL = binDirectory.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let command = AICommandBuilder.buildCodexSession(
            homeDirectory: directory.path
        )
        guard command.executable == executableURL.path else {
            throw TestFailure(
                description: "Hermes Codex was not discovered: \(command)"
            )
        }
    }),
    ("builds a read-only ephemeral Coco command", {
        let command = AICommandBuilder.build(
            provider: .coco,
            prompt: "polish me",
            homeDirectory: "/Users/test",
            outputFile: "/tmp/output.txt"
        )
        guard command.executable == "/Users/test/.local/bin/coco",
              command.arguments.contains("--ignore-user-config"),
              command.arguments.contains("--ephemeral"),
              command.arguments.contains("read-only"),
              command.arguments.contains("/tmp/output.txt") else {
            throw TestFailure(description: "unsafe Coco command: \(command)")
        }
    }),
]
