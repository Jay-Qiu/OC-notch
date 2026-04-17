import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "ProcessScanner")

/// Scans running processes to find OpenCode instances with HTTP servers.
actor ProcessScanner {
    /// Find all opencode processes that are listening on a port.
    func findInstances() -> [OCInstance] {
        var instances: [OCInstance] = []

        // Get all opencode PIDs
        let pids = findOpenCodePIDs()
        guard pids.isEmpty == false else {
            logger.info("No opencode processes found")
            return []
        }

        logger.info("Found \(pids.count) opencode processes")

        // For each PID, check if it's listening on a port
        for pid in pids {
            if let port = findListeningPort(pid: pid) {
                let instance = OCInstance(
                    id: "pid-\(pid)",
                    pid: pid,
                    port: port,
                    hostname: "127.0.0.1"
                )
                instances.append(instance)
                logger.info("Found OpenCode instance: PID \(pid) on port \(port)")
            }
        }

        return instances
    }

    // MARK: - Private

    /// Find PIDs of running opencode processes using `pgrep`.
    private func findOpenCodePIDs() -> [Int32] {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "opencode"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            logger.error("Failed to run pgrep: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Check if a process is listening on a TCP port using `lsof`.
    private func findListeningPort(pid: Int32) -> Int? {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", "-P", "-n", "-p", "\(pid)"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Look for LISTEN lines like: "opencode 39562 jquach 9u IPv4 ... TCP 127.0.0.1:4096 (LISTEN)"
        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.contains("LISTEN") && lineStr.contains("opencode") {
                // Extract port from "host:port"
                if let portRange = lineStr.range(of: #":(\d+)\s+\(LISTEN\)"#, options: .regularExpression) {
                    let match = lineStr[portRange]
                    let portStr = match.split(separator: ":").last?.replacingOccurrences(of: " (LISTEN)", with: "") ?? ""
                    if let port = Int(portStr) {
                        return port
                    }
                }
            }
        }

        return nil
    }
}
