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
    @State private var questionQueue = QuestionQueueManager()
    @State private var notchState: NotchState = .collapsed
    @State private var isHovering = false
    @State private var clickOutsideMonitor: Any?
    @State private var themeManager = ThemeManager.shared
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
    @State private var currentNotchHeight: CGFloat = {
        NSScreen.targetScreen?.auxiliaryTopLeftArea?.height ?? 32
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
            questionQueue.sync(with: newQuestions)

            if !questionQueue.isEmpty && notchState != .permission {
                if newQuestions.count > oldQuestions.count {
                    userDismissed = false
                }
                if !userDismissed {
                    notchState = .question
                }
            } else if questionQueue.isEmpty && notchState == .question {
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
            .opacity(pillRevealOpacity)
            .frame(height: 36 * currentDisplayScale)
            .frame(maxWidth: currentNotchWidth + 100 * currentDisplayScale)
            .padding(.horizontal, 8 * currentDisplayScale)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radii.compactBottom, style: .continuous)
                        .fill(DS.Colors.pillBackground)
                        .opacity(pillRevealOpacity)
                    RoundedRectangle(cornerRadius: DS.Radii.compactBottom, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(isHovering && notchState == .collapsed ? 1 : 0)
                    NeoHaloOverlay(
                        state: currentHaloState,
                        cornerRadius: DS.Radii.compactBottom,
                        thinkingNotchSize: thinkingNotchSize
                    )
                }
                .animation(DS.Animations.smooth, value: isHovering)
                .animation(DS.Animations.smooth, value: themeManager.current)
                .animation(DS.Animations.smooth, value: notchState)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radii.compactBottom, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    /// Opacity of the visible pill (background + content). In Neo theme the pill
    /// is hidden at rest so only the halo is visible, and reappears on hover or
    /// when the notch is expanded.
    private var pillRevealOpacity: Double {
        if themeManager.current != .neo { return 1 }
        if notchState != .collapsed { return 1 }
        return isHovering ? 1 : 0
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

                    if permissionQueue.count > 1 {
                        queuePagination
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { focusSession(request.sessionID) }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        case .question:
            if let request = questionQueue.currentQuestion {
                VStack(spacing: 0) {
                    questionSessionHeader

                    QuestionRequestView(request: request)
                        .id(questionQueue.activeSessionID)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )

                    dismissSessionLink
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: questionQueue.activeSessionID)
                .contentShape(Rectangle())
                .onTapGesture { focusSession(questionQueue.activeSessionID) }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        case .notification(let completion):
            TaskCompletionView(completion: completion)
        case .dropdown:
            SessionDropdownView(
                questionQueue: questionQueue,
                onDismiss: { notchState = .collapsed },
                onResumeSession: { sessionID in
                    questionQueue.resumeSession(sessionID)
                    notchState = .question
                }
            )
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
            } else if !questionQueue.isEmpty {
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

    // MARK: - Focus Terminal

    private func focusSession(_ sessionID: String?) {
        guard let sessionID,
              let session = monitor.activeSessions.first(where: { $0.id == sessionID })
        else { return }
        TerminalLauncher.activateTerminal(
            tab: monitor.terminalTabForSession(sessionID),
            pid: monitor.pidForSession(sessionID),
            directory: session.directory
        )
    }

    private func handleDismissCurrentQuestion() {
        guard let question = questionQueue.currentQuestion else { return }
        questionQueue.dismiss(questionID: question.id)
        if questionQueue.isEmpty {
            notchState = .collapsed
            userDismissed = true
        }
    }

    private func handleDismissSession() {
        guard let sessionID = questionQueue.activeSessionID else { return }
        questionQueue.dismissSession(sessionID)
        if questionQueue.isEmpty {
            notchState = .collapsed
            userDismissed = true
        }
    }

    // MARK: - Question Session Header

    private var questionSessionHeader: some View {
        HStack(spacing: DS.Spacing.elementSpacing) {
            if let sessionID = questionQueue.activeSessionID,
               let session = monitor.activeSessions.first(where: { $0.id == sessionID }) {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Colors.accentBlue)

                Text(session.title)
                    .font(DS.Typography.caption())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if questionQueue.currentSessionQuestionCount > 1 {
                Text("\(questionQueue.currentSessionQuestionCount) questions")
                    .font(DS.Typography.micro())
                    .foregroundStyle(DS.Colors.textTertiary)
            }

            if questionQueue.waitingSessionCount > 0 {
                Text("+\(questionQueue.waitingSessionCount) session\(questionQueue.waitingSessionCount > 1 ? "s" : "") en attente")
                    .font(DS.Typography.micro())
                    .foregroundStyle(DS.Colors.accentOrange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DS.Colors.accentOrange.opacity(0.12))
                    )
            }

            Button { handleDismissCurrentQuestion() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(DS.Colors.elevatedSurface)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, DS.Spacing.elementSpacing)
    }

    private var dismissSessionLink: some View {
        HStack {
            Spacer()
            Button { handleDismissSession() } label: {
                Text("Ignorer cette session")
                    .font(DS.Typography.micro())
                    .foregroundStyle(DS.Colors.textTertiary)
                    .underline()
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, DS.Spacing.elementSpacing)
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

    // MARK: - Halo State

    /// Size of the hardware notch (or a sensible default on non-notched
    /// displays). Used to constrain the `.thinking` halo to the inner notch
    /// shape instead of the full pill bar.
    private var thinkingNotchSize: CGSize {
        CGSize(width: currentNotchWidth, height: currentNotchHeight)
    }

    private var currentHaloState: NeoHaloState {
        guard themeManager.current == .neo else { return .none }
        if !monitor.pendingPermissions.isEmpty { return .permission }
        if !monitor.pendingQuestions.isEmpty { return .question }
        if monitor.activeSessions.contains(where: { $0.status == .busy }) { return .thinking }
        return .none
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
            currentNotchHeight = leftArea.height
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
