import AppKit
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "TerminalLauncher")

/// Utility for activating terminal applications to focus a specific session.
enum TerminalLauncher {
    /// Known terminal bundle IDs in preference order
    private static let terminalBundleIDs = [
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.apple.Terminal",
    ]

    /// Activate the user's terminal app (best effort — can't target a specific tab/pane)
    @MainActor
    static func activateTerminal() {
        // Find the first running terminal
        for bundleID in terminalBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
                logger.info("Activated terminal: \(bundleID)")
                return
            }
        }

        // Fallback: try Apple Terminal
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: .init())
            logger.info("Opened Apple Terminal as fallback")
        } else {
            logger.warning("No terminal application found")
        }
    }
}
