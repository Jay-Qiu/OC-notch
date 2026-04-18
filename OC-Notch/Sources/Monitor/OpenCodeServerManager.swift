import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "ServerManager")

/// Manages a child `opencode serve` process tied to the app lifecycle.
/// Launches on start, parses the bound port from stdout, kills on terminate.
@MainActor
@Observable
final class OpenCodeServerManager {
    private(set) var port: Int?
    private(set) var isRunning = false

    private var process: Process?
    private let outputPipe = Pipe()
    private var outputBuffer = ""

    func start() {
        let opencodePath = findOpenCode()
        guard let opencodePath else {
            logger.error("opencode not found in PATH or /opt/homebrew/bin")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: opencodePath)
        p.arguments = ["serve", "--port", "0"]
        p.standardOutput = outputPipe
        p.standardError = outputPipe

        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            logger.info("opencode serve exited with status \(code)")
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.port = nil
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.handleOutput(chunk)
            }
        }

        do {
            try p.run()
            process = p
            isRunning = true
            logger.info("Launched opencode serve (PID \(p.processIdentifier))")
        } catch {
            logger.error("Failed to launch opencode serve: \(error)")
        }
    }

    func stop() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        guard let p = process, p.isRunning else { return }

        p.terminate()
        let pid = p.processIdentifier
        logger.info("Sent SIGTERM to opencode serve (PID \(pid))")

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if p.isRunning {
                kill(pid, SIGKILL)
                logger.warning("Force-killed opencode serve (PID \(pid))")
            }
        }
        process = nil
        isRunning = false
        port = nil
    }

    // MARK: - Private

    private func handleOutput(_ chunk: String) {
        outputBuffer += chunk
        // Parse: "opencode server listening on http://127.0.0.1:PORT"
        if let range = outputBuffer.range(of: #"listening on http://[^:]+:(\d+)"#, options: .regularExpression) {
            let match = outputBuffer[range]
            if let colonRange = match.range(of: #":\d+$"#, options: .regularExpression) {
                let portStr = match[colonRange].dropFirst()
                if let parsed = Int(portStr) {
                    port = parsed
                    logger.info("opencode serve bound to port \(parsed)")
                }
            }
        }
    }

    private func findOpenCode() -> String? {
        let candidates = [
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try PATH via which
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["opencode"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }
}
