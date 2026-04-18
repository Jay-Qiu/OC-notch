import AppKit
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "TerminalLauncher")

enum TerminalLauncher {
    private static let terminalBundleIDs = [
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.apple.Terminal",
    ]

    @MainActor
    static func activateTerminal() {
        activateTerminal(directory: nil)
    }

    @MainActor
    static func activateTerminal(directory: String?) {
        let tty: String? = directory.flatMap { findTTY(forDirectory: $0) }

        for bundleID in terminalBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
                if let dir = directory {
                    focusWindowForDirectory(bundleID: bundleID, directory: dir, tty: tty)
                }
                logger.notice("Activated terminal: \(bundleID)")
                return
            }
        }

        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: .init())
            logger.notice("Opened Apple Terminal as fallback")
        } else {
            logger.warning("No terminal application found")
        }
    }

    // MARK: - Window Focus

    private static func focusWindowForDirectory(bundleID: String, directory: String, tty: String?) {
        switch bundleID {
        case "com.mitchellh.ghostty":
            focusGhosttyWindow(directory: directory)
        case "com.googlecode.iterm2":
            focusiTermWindow(directory: directory, tty: tty)
        case "com.apple.Terminal":
            focusAppleTerminalWindow(directory: directory, tty: tty)
        default:
            break
        }
    }

    private static func focusGhosttyWindow(directory: String) {
        let dirName = (directory as NSString).lastPathComponent
        let script = """
            tell application "Ghostty"
                activate
                set targetDir to "\(directory)"
                set targetName to "\(dirName)"
                repeat with w in windows
                    set wName to name of w
                    if wName contains targetDir or wName contains targetName then
                        set index of w to 1
                        return
                    end if
                end repeat
            end tell
            """
        logger.notice("Ghostty focus: dir=\(directory) dirName=\(dirName)")
        runAppleScript(script)
    }

    private static func focusiTermWindow(directory: String, tty: String?) {
        let dirName = (directory as NSString).lastPathComponent
        var matchCondition: String
        if let tty {
            matchCondition = "tty of s is \"\(tty)\""
        } else {
            matchCondition = "sName contains \"\(directory)\" or sName contains \"\(dirName)\""
        }

        let script = """
            tell application "iTerm"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set sName to name of s
                            if \(matchCondition) then
                                select t
                                select s
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        logger.notice("iTerm focus: dir=\(directory) tty=\(tty ?? "nil")")
        runAppleScript(script)
    }

    private static func focusAppleTerminalWindow(directory: String, tty: String?) {
        let dirName = (directory as NSString).lastPathComponent
        var matchCondition: String
        if let tty {
            matchCondition = "tty of t is \"\(tty)\""
        } else {
            matchCondition = "custom title of t contains \"\(directory)\" or custom title of t contains \"\(dirName)\""
        }

        let script = """
            tell application "Terminal"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if \(matchCondition) then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        runAppleScript(script)
    }

    // MARK: - TTY Lookup

    private static func findTTY(forDirectory directory: String) -> String? {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axc", "-o", "pid,comm"]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice

        do { try ps.run(); ps.waitUntilExit() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let pids = output.split(separator: "\n").compactMap { line -> Int32? in
            let cols = line.split(separator: " ", maxSplits: 1)
            guard cols.count == 2,
                  cols[1].trimmingCharacters(in: .whitespaces) == "opencode",
                  let pid = Int32(cols[0].trimmingCharacters(in: .whitespaces))
            else { return nil }
            return pid
        }

        for pid in pids {
            guard let cwd = getCWD(pid: pid), cwd == directory else { continue }
            if let tty = getTTY(pid: pid) {
                logger.notice("TTY for dir \(directory): \(tty) (PID \(pid))")
                return tty
            }
        }
        return nil
    }

    private static func getCWD(pid: Int32) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-F", "n"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run(); task.waitUntilExit() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("n") { return String(l.dropFirst()) }
        }
        return nil
    }

    private static func getTTY(pid: Int32) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "tty="]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run(); task.waitUntilExit() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output.isEmpty == false, output != "??"
        else { return nil }

        if output.hasPrefix("/dev/") {
            return output
        }
        return "/dev/\(output)"
    }

    private static func runAppleScript(_ source: String) {
        Task.detached {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let error {
                    logger.error("AppleScript error: \(error)")
                }
            }
        }
    }
}
