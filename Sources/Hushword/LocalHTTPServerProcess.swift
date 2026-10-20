import Foundation

package struct LocalHTTPServerConfiguration {
    package let processLabel: String
    package let executableURL: URL
    package let arguments: [String]
    package let environment: [String: String]
    package let healthURL: URL
    package let maximumStartupChecks: Int
    package let startupCheckIntervalNanoseconds: UInt64

    package init(
        processLabel: String,
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        healthURL: URL,
        maximumStartupChecks: Int = 80,
        startupCheckIntervalNanoseconds: UInt64 = 100_000_000
    ) {
        self.processLabel = processLabel
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.healthURL = healthURL
        self.maximumStartupChecks = max(1, maximumStartupChecks)
        self.startupCheckIntervalNanoseconds = startupCheckIntervalNanoseconds
    }
}

@MainActor
package final class LocalHTTPServerProcess {
    private let configuration: LocalHTTPServerConfiguration
    private var supervisorProcess: Process?
    private var retiringSupervisorProcess: Process?
    private var lifecycleGeneration: UInt64 = 0

    package init(configuration: LocalHTTPServerConfiguration) {
        self.configuration = configuration
    }

    deinit {
        supervisorProcess?.terminate()
        retiringSupervisorProcess?.terminate()
    }

    package func startIfNeeded() async -> Bool {
        if let retiringSupervisorProcess {
            guard await waitUntilShutdownCompletes(
                process: retiringSupervisorProcess
            ) else {
                return false
            }
            if self.retiringSupervisorProcess === retiringSupervisorProcess {
                self.retiringSupervisorProcess = nil
            }
        }

        if let supervisorProcess, supervisorProcess.isRunning {
            if await isHealthy() {
                return true
            }
            let generation = lifecycleGeneration
            let becameHealthy = await waitUntilHealthy(
                process: supervisorProcess
            )
            return becameHealthy
                && generation == lifecycleGeneration
                && self.supervisorProcess === supervisorProcess
        }
        if supervisorProcess != nil {
            self.supervisorProcess = nil
        }
        if await isHealthy() {
            return true
        }

        let process = makeSupervisorProcess()

        do {
            try process.run()
            supervisorProcess = process
        } catch {
            return false
        }
        let generation = lifecycleGeneration
        let becameHealthy = await waitUntilHealthy(process: process)
        return becameHealthy
            && generation == lifecycleGeneration
            && supervisorProcess === process
    }

    package func isHealthy() async -> Bool {
        var request = URLRequest(url: configuration.healthURL)
        request.timeoutInterval = 0.25
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    package func shutdown() {
        lifecycleGeneration &+= 1
        guard let activeSupervisorProcess = supervisorProcess else { return }
        if activeSupervisorProcess.isRunning {
            activeSupervisorProcess.terminate()
        }
        retiringSupervisorProcess = activeSupervisorProcess
        self.supervisorProcess = nil
    }

    private func makeSupervisorProcess() -> Process {
        let script = """
        parent_pid=$1
        server_executable=$2
        shift 2
        "$server_executable" "$@" &
        child_pid=$!
        cleanup() {
          kill "$child_pid" 2>/dev/null || true
          wait "$child_pid" 2>/dev/null || true
        }
        trap cleanup EXIT INT TERM
        while kill -0 "$parent_pid" 2>/dev/null && kill -0 "$child_pid" 2>/dev/null; do
          sleep 1
        done
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            script,
            configuration.processLabel,
            String(ProcessInfo.processInfo.processIdentifier),
            configuration.executableURL.path,
        ] + configuration.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            configuration.environment
        ) { _, override in
            override
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    private func waitUntilHealthy(process: Process) async -> Bool {
        for _ in 0..<configuration.maximumStartupChecks {
            guard !Task.isCancelled else { return false }
            if await isHealthy() {
                return true
            }
            if !process.isRunning {
                return false
            }
            try? await Task.sleep(
                nanoseconds: configuration.startupCheckIntervalNanoseconds
            )
        }
        return false
    }

    private func waitUntilShutdownCompletes(process: Process) async -> Bool {
        for _ in 0..<configuration.maximumStartupChecks {
            if !process.isRunning, await isHealthy() == false {
                return true
            }
            try? await Task.sleep(
                nanoseconds: configuration.startupCheckIntervalNanoseconds
            )
        }
        let healthy = await isHealthy()
        return !process.isRunning && !healthy
    }
}
