import SwiftUI
import Combine

/// The main shell view that sits around the notch.
/// Layout: [Avatar (SpriteKit)] — [Notch Spacer] — [Session Counter]
/// Can expand downward for permission requests, notifications, or session dropdown.
struct NotchShellView: View {
    @Environment(SessionMonitorService.self) private var monitor
    @State private var avatarScene = AvatarScene(size: CGSize(width: 36, height: 36))
    @State private var avatarStateManager = AvatarStateManager()
    @State private var permissionQueue = PermissionQueueManager()
    @State private var notchState: NotchState = .collapsed
    @State private var isHovering = false
    @State private var clickOutsideMonitor: Any?
    /// When `true`, auto-expand for pending permissions/questions is suppressed
    /// until the user clicks the notch bar or a *new* request arrives.
    @State private var userDismissed = false

    // Screen-geometry state — reactive so SwiftUI re-renders on display changes
    @State private var currentDisplayScale: CGFloat = NSScreen.targetScreen?.displayScaleFactor ?? 1.0
    @State private var currentNotchWidth: CGFloat = {
        guard let screen = NSScreen.targetScreen,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return 180 }
        return rightArea.minX - leftArea.maxX
    }()

    var onExpandChange: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            notchBar

            if notchState != .collapsed {
                expandedContent
                    .frame(width: pillWidth)
                    .padding(.vertical, DS.Spacing.cardPadding)
                    .padding(.horizontal, DS.Spacing.cardPadding + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radii.expandedBottom, style: .continuous)
                            .fill(DS.Colors.pillBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radii.expandedBottom, style: .continuous)
                                    .fill(.ultraThinMaterial.opacity(0.3))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radii.expandedBottom, style: .continuous)
                                    .strokeBorder(DS.Colors.separator, lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(DS.Shadows.expandedOpacity), radius: DS.Shadows.expandedRadius, y: DS.Shadows.expandedY)
                    )
                    .padding(.top, DS.Spacing.tightSpacing)
                    .transition(.dynamicIsland())
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(notchState == .collapsed ? DS.Animations.close : DS.Animations.open, value: notchState)
        .onChange(of: monitor.pendingPermissions) { _, newPerms in
            syncPermissionQueue(newPerms)
        }
        .onChange(of: monitor.lastCompletion) { _, completion in
            if let completion, notchState != .permission && notchState != .question {
                notchState = .notification(completion)
            } else if completion == nil && notchState.isNotification {
                notchState = .collapsed
            }
        }
        .onChange(of: monitor.pendingQuestions) { oldQuestions, newQuestions in
            if newQuestions.isEmpty == false && notchState != .permission {
                if newQuestions.count > oldQuestions.count {
                    userDismissed = false
                }
                if !userDismissed {
                    notchState = .question
                }
            } else if newQuestions.isEmpty && notchState == .question {
                notchState = .collapsed
                userDismissed = false
            }
        }
        .onChange(of: avatarStateManager.currentState) { _, newState in
            avatarScene.setState(newState)
        }
        .onChange(of: monitor.pendingPermissions.count) { _, _ in updateAvatarState() }
        .onChange(of: monitor.pendingQuestions.count) { _, _ in updateAvatarState() }
        .onChange(of: monitor.activeSessions) { _, _ in updateAvatarState() }
        .onChange(of: notchState) { _, newState in
            onExpandChange?(newState != .collapsed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchClickedOutside)) { _ in
            switch notchState {
            case .dropdown, .notification:
                notchState = .collapsed
            case .permission, .question:
                userDismissed = true
                notchState = .collapsed
            case .collapsed:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateScreenMetrics()
        }
    }

    // MARK: - Notch Bar

    private var notchBar: some View {
        Button(action: toggleDropdown) {
            HStack(spacing: 0) {
                AvatarView(scene: avatarScene, size: 36 * currentDisplayScale)
                    .padding(.trailing, 8 * currentDisplayScale)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .clipped()

                Spacer()
                    .frame(width: currentNotchWidth)

                SessionCounterView()
                    .padding(.leading, 8 * currentDisplayScale)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 36 * currentDisplayScale)
            .frame(maxWidth: currentNotchWidth + 100 * currentDisplayScale)
            .padding(.horizontal, 8 * currentDisplayScale)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radii.compactBottom, style: .continuous)
                        .fill(DS.Colors.pillBackground)
                    RoundedRectangle(cornerRadius: DS.Radii.compactBottom, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(isHovering && notchState == .collapsed ? 1 : 0)
                }
                .animation(DS.Animations.smooth, value: isHovering)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radii.compactBottom, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        switch notchState {
        case .collapsed:
            EmptyView()
        case .permission:
            if let request = permissionQueue.current {
                VStack(spacing: 0) {
                    PermissionRequestView(request: request)

                    // Queue pagination dots
                    if permissionQueue.count > 1 {
                        queuePagination
                    }
                }
            }
        case .question:
            if let request = monitor.pendingQuestions.first {
                QuestionRequestView(request: request)
            }
        case .notification(let completion):
            TaskCompletionView(completion: completion)
        case .dropdown:
            SessionDropdownView(onDismiss: { notchState = .collapsed })
        }
    }

    // MARK: - Dropdown Toggle

    private func toggleDropdown() {
        switch notchState {
        case .dropdown:
            notchState = .collapsed
        case .collapsed:
            userDismissed = false
            if !permissionQueue.isEmpty {
                notchState = .permission
            } else if !monitor.pendingQuestions.isEmpty {
                notchState = .question
            } else {
                notchState = .dropdown
            }
        case .notification:
            notchState = .dropdown
        case .permission, .question:
            userDismissed = true
            notchState = .collapsed
        }
    }

    // MARK: - Queue Pagination

    private var queuePagination: some View {
        HStack(spacing: DS.Spacing.elementSpacing) {
            Button {
                permissionQueue.previous()
            } label: {
                Image(systemName: "chevron.left")
                    .font(DS.Typography.micro())
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            ForEach(0..<permissionQueue.count, id: \.self) { index in
                Circle()
                    .fill(index == permissionQueue.currentIndex ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                    .frame(width: 5, height: 5)
            }

            Button {
                permissionQueue.next()
            } label: {
                Image(systemName: "chevron.right")
                    .font(DS.Typography.micro())
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            Text("\(permissionQueue.currentIndex + 1)/\(permissionQueue.count)")
                .font(DS.Typography.micro())
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .padding(.vertical, DS.Spacing.elementSpacing)
    }

    // MARK: - State Sync

    private func syncPermissionQueue(_ permissions: [OCPermissionRequest]) {
        // Add new permissions
        let existingIDs = Set(permissionQueue.queue.map(\.id))
        var hasNewArrivals = false
        for perm in permissions where existingIDs.contains(perm.id) == false {
            permissionQueue.enqueue(perm)
            hasNewArrivals = true
        }

        // Remove resolved permissions
        let activeIDs = Set(permissions.map(\.id))
        for existing in permissionQueue.queue where activeIDs.contains(existing.id) == false {
            permissionQueue.remove(requestID: existing.id)
        }

        if hasNewArrivals {
            userDismissed = false
        }

        // Update notch state — permission always takes priority
        if permissionQueue.isEmpty == false {
            if !userDismissed {
                notchState = .permission
            }
        } else if notchState == .permission {
            notchState = .collapsed
            userDismissed = false
        }
    }

    private func updateAvatarState() {
        avatarStateManager.update(
            hasPendingPermissions: monitor.pendingPermissions.isEmpty == false,
            hasActiveSessions: monitor.activeSessions.contains { $0.status == .busy },
            lastCompletion: monitor.lastCompletion
        )
    }

    // MARK: - Click Outside

    private func updateClickOutsideMonitor(expanded: Bool) {
        if expanded {
            guard clickOutsideMonitor == nil else { return }
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [self] event in
                guard let panel = NSApp.windows.first(where: { $0 is NotchPanel }) else { return }
                let mouseLocation = NSEvent.mouseLocation
                if !panel.frame.contains(mouseLocation) {
                    notchState = .collapsed
                }
            }
        } else {
            if let monitor = clickOutsideMonitor {
                NSEvent.removeMonitor(monitor)
                clickOutsideMonitor = nil
            }
        }
    }

    // MARK: - Notch Width

    private var pillWidth: CGFloat {
        max(currentNotchWidth + 220 * currentDisplayScale, 460 * currentDisplayScale)
    }

    private func updateScreenMetrics() {
        currentDisplayScale = NSScreen.targetScreen?.displayScaleFactor ?? 1.0
        if let screen = NSScreen.targetScreen,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            currentNotchWidth = rightArea.minX - leftArea.maxX
        }
    }
}

// MARK: - NotchState

enum NotchState: Equatable {
    case collapsed
    case permission
    case question
    case notification(TaskCompletionInfo)
    case dropdown

    var isNotification: Bool {
        if case .notification = self { return true }
        return false
    }
}
