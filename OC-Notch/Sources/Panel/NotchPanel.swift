import AppKit
import SwiftUI

// MARK: - PassthroughView

final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point) else { return nil }
        // Pass through clicks that land on this container or its layer-hosting parent.
        // Only intercept if a real SwiftUI control caught the hit.
        if result === self { return nil }
        return result
    }
}

// MARK: - NotchPanel

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

        let passthrough = PassthroughView()
        passthrough.wantsLayer = true
        contentView = passthrough
    }
}

// MARK: - NotchPanelController

@MainActor
final class NotchPanelController {
    private var panel: NotchPanel?
    private var screenObserver: Any?
    private var stateObserver: Any?
    let sessionMonitor = SessionMonitorService()

    private static let collapsedHeight: CGFloat = 44
    private static let expandedHeight: CGFloat = 420

    func showPanel() {
        let frame = calculateNotchFrame(expanded: false)
        let panel = NotchPanel(contentRect: frame)

        let shellView = NotchShellView(onExpandChange: { [weak self] expanded in
            self?.updatePanelSize(expanded: expanded)
        })
            .environment(sessionMonitor)

        let hostingView = NSHostingView(rootView: shellView)
        hostingView.frame = panel.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView?.addSubview(hostingView)
        panel.orderFrontRegardless()

        self.panel = panel

        observeScreenChanges()

        Task {
            await sessionMonitor.startMonitoring()
        }
    }

    func updatePanelSize(expanded: Bool) {
        guard let panel else { return }
        let newFrame = calculateNotchFrame(expanded: expanded)
        panel.setFrame(newFrame, display: true, animate: true)
    }

    // MARK: - Notch Geometry

    private func calculateNotchFrame(expanded: Bool) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 400, height: Self.collapsedHeight)
        }

        let screenFrame = screen.frame

        let notchWidth: CGFloat
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchW = rightArea.minX - leftArea.maxX
            notchWidth = notchW + 240
        } else {
            notchWidth = 400
        }

        let width = min(notchWidth, screenFrame.width)
        let height = expanded ? Self.expandedHeight : Self.collapsedHeight
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
        let newFrame = calculateNotchFrame(expanded: false)
        panel.setFrame(newFrame, display: true, animate: false)
    }
}
