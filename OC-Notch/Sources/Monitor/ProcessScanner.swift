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
            logger.notice("No opencode processes found")
            return []
        }

        logger.notice("Found \(pids.count) opencode processes")

        for pid in pids {
            if let port = findListeningPort(pid: pid) {
                let instance = OCInstance(
                    id: "pid-\(pid)",
                    pid: pid,
                    port: port,
                    hostname: "127.0.0.1"
                )
                instances.append(instance)
                logger.notice("Found OpenCode instance: PID \(pid) on port \(port)")
            }
        }

        return instances
    }

    func countProcesses() -> Int {
        findOpenCodePIDs().count
    }

    func findActiveDirectories() -> [String] {
        let pids = findOpenCodePIDs()
        var dirs: [String] = []
        for pid in pids {
            if let cwd = getCWD(pid: pid) {
                dirs.append(cwd)
            }
        }
        return dirs
    }

    // MARK: - Private

    /// Find PIDs of running opencode processes using `pgrep`.
    private func findOpenCodePIDs() -> [Int32] {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axc", "-o", "pid,comm"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            logger.error("Failed to run ps: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return output
            .split(separator: "\n")
            .compactMap { line -> Int32? in
                let cols = line.split(separator: " ", maxSplits: 1)
                guard cols.count == 2,
                      cols[1].trimmingCharacters(in: .whitespaces) == "opencode",
                      let pid = Int32(cols[0].trimmingCharacters(in: .whitespaces))
                else { return nil }
                return pid
            }
            .filter { $0 != ownPID }
    }

    /// Check if a process is listening on a TCP port using `lsof`.
    private func findListeningPort(pid: Int32) -> Int? {
        let task = Process()
        let pipe = Pipe()

        // Use -a to AND the filters: only show network files (-i) for this PID (-p)
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-i", "TCP", "-P", "-n", "-p", "\(pid)"]
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

        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            guard lineStr.contains("LISTEN") else { continue }

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

    private func getCWD(pid: Int32) -> String? {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-F", "n"]
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

        for line in output.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("n") {
                return String(l.dropFirst())
            }
        }
        return nil
    }
}
