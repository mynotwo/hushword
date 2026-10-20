import Foundation

package struct WhisperRuntime: Equatable, Sendable {
    package let serverExecutableURL: URL
    package let cliExecutableURL: URL?
    package let environment: [String: String]
}

package enum WhisperRuntimeLocator {
    package static func locate(
        appBundleURL: URL = Bundle.main.bundleURL,
        cpuBrand: String = detectedCPUBrand(),
        homebrewPrefixes: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew"),
            URL(fileURLWithPath: "/usr/local"),
        ],
        fileManager: FileManager = .default
    ) -> WhisperRuntime? {
        let bundledServer = appBundleURL
            .appendingPathComponent("Contents/Resources/WhisperRuntime")
            .appendingPathComponent(
                "whisper-server-\(runtimeVariant(for: cpuBrand))"
            )
        if fileManager.isExecutableFile(atPath: bundledServer.path) {
            let bundledCLI = bundledServer
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "whisper-cli-\(runtimeVariant(for: cpuBrand))"
                )
            return WhisperRuntime(
                serverExecutableURL: bundledServer,
                cliExecutableURL: fileManager.isExecutableFile(
                    atPath: bundledCLI.path
                ) ? bundledCLI : nil,
                environment: [:]
            )
        }

        for prefix in homebrewPrefixes {
            let server = prefix.appendingPathComponent("bin/whisper-server")
            guard fileManager.isExecutableFile(atPath: server.path) else {
                continue
            }
            let cli = prefix.appendingPathComponent("bin/whisper-cli")
            return WhisperRuntime(
                serverExecutableURL: server,
                cliExecutableURL: fileManager.isExecutableFile(
                    atPath: cli.path
                ) ? cli : nil,
                environment: [:]
            )
        }
        return nil
    }

    package static func runtimeVariant(for cpuBrand: String) -> String {
        let normalized = cpuBrand.lowercased()
        if normalized.contains("apple m4")
            || normalized.contains("apple m5") {
            return "apple_m4"
        }
        if normalized.contains("apple m2")
            || normalized.contains("apple m3") {
            return "apple_m2_m3"
        }
        return "apple_m1"
    }

    private static func detectedCPUBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 0 else {
            return ""
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(
            "machdep.cpu.brand_string",
            &value,
            &size,
            nil,
            0
        ) == 0 else {
            return ""
        }
        return String(cString: value)
    }
}
