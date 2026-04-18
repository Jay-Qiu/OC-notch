import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "ProcessScanner")

/// Scans running processes to find OpenCode instances with HTTP servers.
actor ProcessScanner {
    /// Find all opencode processes that are listening on a port.
    func findInstances() -> [OCInstance] {
        var instances: [OCInstance] = []

        let pids = findOpenCodePIDs()
        guard pids.isEmpty == false else {
            logger.info("No opencode processes found")
            return []
        }

        logger.info("Found \(pids.count) opencode processes")

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

    func countProcesses() -> Int {
        findOpenCodePIDs().count
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

        // lsof with -i + -p uses OR semantics — filter lines by matching PID column
        let pidStr = "\(pid)"
        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            guard lineStr.contains("LISTEN") else { continue }

            // Parse PID from second column: "opencode  39562 jquach ..."
            let columns = lineStr.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2, String(columns[1]) == pidStr else { continue }

            // Extract port from "host:port (LISTEN)"
            if let portRange = lineStr.range(of: #":(\d+)\s+\(LISTEN\)"#, options: .regularExpression) {
                let match = lineStr[portRange]
                let portStr = match.split(separator: ":").last?.replacingOccurrences(of: " (LISTEN)", with: "") ?? ""
                if let port = Int(portStr) {
                    return port
                }
            }
        }

        return nil
    }
}
