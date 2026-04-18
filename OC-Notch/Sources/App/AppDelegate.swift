import AppKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.oc-notch.app", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.warning("OC-Notch launched")
        panelController = NotchPanelController()
        panelController?.showPanel()
        logger.warning("Panel shown, monitoring started")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
