import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var serverManager: OpenCodeServerManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = OpenCodeServerManager()
        manager.start()
        serverManager = manager

        panelController = NotchPanelController()
        panelController?.showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverManager?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
