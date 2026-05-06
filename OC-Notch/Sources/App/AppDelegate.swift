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

        AppRelocator.moveToApplicationsIfNeeded()

        panelController = NotchPanelController()
        panelController?.showPanel()
        logger.warning("Panel shown, monitoring started")

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
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

// MARK: - Sparkle user-driver delegate

extension AppDelegate: SPUStandardUserDriverDelegate {
    /// Sparkle is about to show a modal alert (update prompt, error, etc.). Collapse
    /// the always-on-top notch pill so the alert isn't trapped behind it.
    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .notchClickedOutside, object: nil)
        }
    }

    /// Sparkle's modal is now on screen. Bring the app forward so the alert
    /// isn't hidden behind other windows.
    nonisolated func standardUserDriverDidShowModalAlert() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible && $0.level == .normal }?.orderFrontRegardless()
        }
    }
}
