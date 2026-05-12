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
        activateTerminal(tab: nil, pid: nil, directory: nil)
    }

    @MainActor
    static func activateTerminal(pid: Int32?, directory: String?) {
        activateTerminal(tab: nil, pid: pid, directory: directory)
    }

    @MainActor
    static func activateTerminal(tab: TerminalTab?, pid: Int32?, directory: String?) {
        if let tab {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: tab.bundleID).first {
                app.activate()
                focusTerminalTab(tab, directory: directory)
                logger.notice("Activated terminal via probe: \(tab.bundleID) tty=\(tab.tty)")
                return
            }
        }

        let tty: String?
        if let pid {
            tty = getTTY(pid: pid)
        } else {
            tty = directory.flatMap { findTTY(forDirectory: $0) }
        }

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

    private static func focusTerminalTab(_ tab: TerminalTab, directory: String?) {
        switch tab.bundleID {
        case "com.googlecode.iterm2":
            focusiTermWindow(iTermSessionID: tab.sessionID, tty: tab.tty, directory: directory)
        case "com.mitchellh.ghostty":
            focusGhosttyWindow(directory: directory ?? "", tty: tab.tty)
        case "com.apple.Terminal":
            focusAppleTerminalWindow(directory: directory ?? "", tty: tab.tty)
        default:
            break
        }
    }

    private static func focusWindowForDirectory(bundleID: String, directory: String, tty: String?) {
        switch bundleID {
        case "com.mitchellh.ghostty":
            focusGhosttyWindow(directory: directory, tty: tty)
        case "com.googlecode.iterm2":
            focusiTermWindow(directory: directory, tty: tty)
        case "com.apple.Terminal":
            focusAppleTerminalWindow(directory: directory, tty: tty)
        default:
            break
        }
    }

    private static func focusGhosttyWindow(directory: String, tty: String?) {
        let dirName = (directory as NSString).lastPathComponent

        let ttyMatchBlock: String
        if let tty {
            ttyMatchBlock = """
                set targetTTY to "\(tty)"
                repeat with w in windows
                    set wName to name of w
                    if wName contains targetTTY then
                        set index of w to 1
                        return
                    end if
                end repeat
                """
        } else {
            ttyMatchBlock = ""
        }

        let script = """
            tell application "Ghostty"
                activate
                \(ttyMatchBlock)
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
        logger.notice("Ghostty focus: dir=\(directory) dirName=\(dirName) tty=\(tty ?? "nil")")
        runAppleScript(script)
    }

    private static func focusiTermWindow(directory: String, tty: String?) {
        focusiTermWindow(iTermSessionID: nil, tty: tty, directory: directory)
    }

    private static func focusiTermWindow(iTermSessionID: String?, tty: String?, directory: String?) {
        let dirName = directory.map { ($0 as NSString).lastPathComponent }
        let normalizedDir = directory.map { normalizePath($0) }

        // Priority: iTerm session ID → TTY → directory name
        var matchBlocks: [String] = []

        if let iTermSessionID, iTermSessionID.isEmpty == false {
            matchBlocks.append("""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (id of s as text) is "\(iTermSessionID)" then
                                tell w
                                    set current tab to t
                                end tell
                                tell t
                                    set current session to s
                                end tell
                                set index of w to 1
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
                """)
        }

        if let tty {
            matchBlocks.append("""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell w
                                    set current tab to t
                                end tell
                                tell t
                                    set current session to s
                                end tell
                                set index of w to 1
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
                """)
        }

        if let normalizedDir, let dirName {
            matchBlocks.append("""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set sName to name of s
                            if sName contains "\(normalizedDir)" or sName contains "\(dirName)" then
                                tell w
                                    set current tab to t
                                end tell
                                tell t
                                    set current session to s
                                end tell
                                set index of w to 1
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
                """)
        }

        let script = """
            tell application "iTerm"
                activate
                \(matchBlocks.joined(separator: "\n            "))
            end tell
            """
        logger.notice("iTerm focus: dir=\(directory ?? "nil") sessionID=\(iTermSessionID ?? "nil") tty=\(tty ?? "nil")")
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

    private static func normalizePath(_ path: String) -> String {
        // Resolve /private prefix (macOS symlinks /tmp -> /private/tmp, /var -> /private/var)
        let resolved = (path as NSString).resolvingSymlinksInPath
        if resolved.hasSuffix("/") && resolved.count > 1 {
            return String(resolved.dropLast())
        }
        return resolved
    }

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

        let normalizedDir = normalizePath(directory)
        for pid in pids {
            guard let cwd = getCWD(pid: pid), normalizePath(cwd) == normalizedDir else { continue }
            if let tty = getTTY(pid: pid) {
                logger.notice("TTY for dir \(directory): \(tty) (PID \(pid))")
                return tty
            }
        }
        logger.notice("No TTY found for dir \(directory) among \(pids.count) opencode processes")
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
            let task = Process()
            let errPipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", source]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = errPipe

            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    logger.error("AppleScript failed (\(task.terminationStatus)): \(errStr)")
                }
            } catch {
                logger.error("Failed to run osascript: \(error)")
            }
        }
    }
}
