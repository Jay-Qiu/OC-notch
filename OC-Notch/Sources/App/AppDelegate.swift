import AppKit
import os
import Sparkle
import SwiftUI

private let logger = Logger(subsystem: "com.oc-notch.app", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?

    /// Gracefully no-ops if SUPublicEDKey in Info.plist is still the placeholder value.
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.warning("OC-Notch launched")

        panelController = NotchPanelController()
        panelController?.showPanel()
        logger.warning("Panel shown, monitoring started")

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Sparkle

    var sparkleUpdater: SPUUpdater? {
        updaterController?.updater
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }
}
