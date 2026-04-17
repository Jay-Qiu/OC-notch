import AppKit
import SwiftUI

// MARK: - NotchPanel

/// A non-activating, borderless, transparent NSPanel that overlays the notch area.
/// Never steals keyboard focus from the user's active application.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
    }
}

// MARK: - NotchPanelController

/// Manages the NotchPanel lifecycle: creation, positioning, and screen change observation.
@MainActor
final class NotchPanelController {
    private var panel: NotchPanel?
    private var screenObserver: Any?
    private let sessionMonitor = SessionMonitorService()

    func showPanel() {
        let frame = calculateNotchFrame()
        let panel = NotchPanel(contentRect: frame)

        let hostingView = NSHostingView(
            rootView: NotchShellView()
                .environment(sessionMonitor)
        )
        hostingView.frame = panel.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView?.addSubview(hostingView)
        panel.orderFrontRegardless()

        self.panel = panel

        observeScreenChanges()

        // Start monitoring OpenCode sessions
        Task {
            await sessionMonitor.startMonitoring()
        }
    }

    // MARK: - Notch Geometry

    /// Calculate the frame that spans the full menu bar area (left auxiliary + notch + right auxiliary).
    /// Uses screen-global coordinates for correct NSPanel positioning.
    private func calculateNotchFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 400, height: 38)
        }

        let screenFrame = screen.frame

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            // auxiliaryTopLeftArea/auxiliaryTopRightArea are in screen-local coordinates.
            // The panel spans the full top bar: from x=0 to the full screen width.
            // Height = safeAreaInsets.top (the menu bar / notch height).
            let height = screen.safeAreaInsets.top
            let width = screenFrame.width
            let x = screenFrame.origin.x
            let y = screenFrame.maxY - height

            return NSRect(x: x, y: y, width: width, height: height)
        }

        // Fallback for screens without a notch: center a bar at the top
        let width: CGFloat = 400
        let height: CGFloat = 38
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.maxY - height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Screen Observation

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPanel()
            }
        }
    }

    private func repositionPanel() {
        guard let panel else { return }
        let newFrame = calculateNotchFrame()
        panel.setFrame(newFrame, display: true, animate: false)
    }
}
