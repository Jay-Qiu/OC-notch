import AppKit
import SwiftUI

extension Notification.Name {
    static let notchClickedOutside = Notification.Name("notchClickedOutside")
}

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

// MARK: - ClickCatcherWindow

final class ClickCatcherWindow: NSWindow {
    var onMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen?) {
        super.init(
            contentRect: screen?.frame ?? NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

// MARK: - NotchPanel

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
final class NotchPanelController: NSObject, NSMenuDelegate {
    private var panel: NotchPanel?
    private var screenObserver: Any?
    private var stateObserver: Any?
    private var clickCatcher: ClickCatcherWindow?
    private var themeMenuItems: [NotchTheme: NSMenuItem] = [:]
    let sessionMonitor = SessionMonitorService()

    private static let collapsedHeight: CGFloat = 44
    private static let expandedHeight: CGFloat = 520

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
        let menu = buildContextMenu()
        menu.delegate = self
        panel.contentView?.menu = menu
        panel.orderFrontRegardless()

        self.panel = panel

        observeScreenChanges()
        observePanelVisibility()

        Task {
            await sessionMonitor.startMonitoring()
        }
    }

    func updatePanelSize(expanded: Bool) {
        guard let panel else { return }
        let newFrame = calculateNotchFrame(expanded: expanded)
        panel.setFrame(newFrame, display: true, animate: true)
        updateClickOutsideMonitor(expanded: expanded)
    }

    // MARK: - Click Outside Detection

    private func updateClickOutsideMonitor(expanded: Bool) {
        if expanded {
            guard clickCatcher == nil else { return }
            let catcher = ClickCatcherWindow(screen: NSScreen.targetScreen)
            catcher.onMouseDown = { [weak self] in
                NotificationCenter.default.post(name: .notchClickedOutside, object: nil)
            }
            catcher.orderFrontRegardless()
            panel?.orderFrontRegardless()
            clickCatcher = catcher
        } else {
            clickCatcher?.orderOut(nil)
            clickCatcher = nil
        }
    }

    // MARK: - Notch Geometry

    private func calculateNotchFrame(expanded: Bool) -> NSRect {
        guard let screen = NSScreen.targetScreen else {
            return NSRect(x: 0, y: 0, width: 400, height: Self.collapsedHeight)
        }

        let screenFrame = screen.frame

        let notchWidth: CGFloat
        let height: CGFloat

        if screen.hasNotch,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchW = rightArea.minX - leftArea.maxX
            let scale = screen.displayScaleFactor
            let collapsedPad = 124 * scale
            let expandedPad = 380 * scale

            notchWidth = expanded ? notchW + expandedPad : notchW + collapsedPad
            height = expanded ? Self.expandedHeight * scale : Self.collapsedHeight * scale
        } else {
            notchWidth = expanded ? 580 : 400
            height = expanded ? Self.expandedHeight : Self.collapsedHeight
        }

        let width = min(notchWidth, screenFrame.width)
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.maxY - height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let aboutItem = NSMenuItem(
            title: "OC-Notch v\(version)",
            action: NSSelectorFromString("orderFrontStandardAboutPanel:"),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        let themeItem = NSMenuItem(title: "Thème", action: nil, keyEquivalent: "")
        themeItem.submenu = buildThemeMenu()
        menu.addItem(themeItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Chercher une mise à jour…",
            action: NSSelectorFromString("checkForUpdates:"),
            keyEquivalent: ""
        )
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quitter OC-Notch",
            action: NSSelectorFromString("terminate:"),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    private func buildThemeMenu() -> NSMenu {
        let submenu = NSMenu(title: "Thème")
        submenu.delegate = self
        themeMenuItems.removeAll()

        for theme in NotchTheme.allCases {
            let item = NSMenuItem(
                title: theme.displayName,
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            submenu.addItem(item)
            themeMenuItems[theme] = item
        }

        refreshThemeMenuState()
        return submenu
    }

    private func refreshThemeMenuState() {
        let current = ThemeManager.shared.current
        for (theme, item) in themeMenuItems {
            item.state = (theme == current) ? .on : .off
        }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = NotchTheme(rawValue: raw) else { return }
        ThemeManager.shared.current = theme
        refreshThemeMenuState()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshThemeMenuState()
    }

    // MARK: - Panel Visibility

    private var isObservingVisibility = false

    private func observePanelVisibility() {
        guard !isObservingVisibility else { return }
        isObservingVisibility = true
        observeVisibilityStep()
    }

    private func observeVisibilityStep() {
        withObservationTracking {
            _ = sessionMonitor.activeSessions
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updatePanelVisibility()
                self?.observeVisibilityStep()
            }
        }
        // Apply immediately so the initial state is correct
        updatePanelVisibility()
    }

    private func updatePanelVisibility() {
        let hasSessions = !sessionMonitor.activeSessions.isEmpty
        panel?.alphaValue = hasSessions ? 1 : 0
        panel?.ignoresMouseEvents = !hasSessions
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
