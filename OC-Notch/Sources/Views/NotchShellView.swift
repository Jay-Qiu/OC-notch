import SwiftUI

/// The main shell view that sits around the notch.
/// Layout: [Avatar (SpriteKit)] — [Notch Spacer] — [Session Counter]
/// Can expand downward for permission requests, notifications, or session dropdown.
struct NotchShellView: View {
    @Environment(SessionMonitorService.self) private var monitor
    @State private var avatarScene = AvatarScene(size: CGSize(width: 36, height: 36))
    @State private var avatarStateManager = AvatarStateManager()
    @State private var permissionQueue = PermissionQueueManager()
    @State private var notchState: NotchState = .collapsed

    var onExpandChange: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            notchBar

            if notchState != .collapsed {
                expandedContent
                    .frame(width: pillWidth)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    )
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: notchState)
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
        .onChange(of: monitor.pendingQuestions) { _, newQuestions in
            if newQuestions.isEmpty == false && notchState != .permission {
                notchState = .question
            } else if newQuestions.isEmpty && notchState == .question {
                notchState = .collapsed
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
    }

    // MARK: - Notch Bar

    private var notchBar: some View {
        HStack(spacing: 0) {
            AvatarView(scene: avatarScene)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer()
                .frame(width: notchWidth)

            SessionCounterView(onTap: toggleDropdown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
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
        case .collapsed, .notification:
            notchState = .dropdown
        case .permission, .question:
            // Permission/question takes priority — do not open dropdown
            break
        }
    }

    // MARK: - Queue Pagination

    private var queuePagination: some View {
        HStack(spacing: 6) {
            Button {
                permissionQueue.previous()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)

            ForEach(0..<permissionQueue.count, id: \.self) { index in
                Circle()
                    .fill(index == permissionQueue.currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
            }

            Button {
                permissionQueue.next()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)

            Text("\(permissionQueue.currentIndex + 1)/\(permissionQueue.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - State Sync

    private func syncPermissionQueue(_ permissions: [OCPermissionRequest]) {
        // Add new permissions
        let existingIDs = Set(permissionQueue.queue.map(\.id))
        for perm in permissions where existingIDs.contains(perm.id) == false {
            permissionQueue.enqueue(perm)
        }

        // Remove resolved permissions
        let activeIDs = Set(permissions.map(\.id))
        for existing in permissionQueue.queue where activeIDs.contains(existing.id) == false {
            permissionQueue.remove(requestID: existing.id)
        }

        // Update notch state — permission always takes priority
        if permissionQueue.isEmpty == false {
            notchState = .permission
        } else if notchState == .permission {
            notchState = .collapsed
        }
    }

    private func updateAvatarState() {
        avatarStateManager.update(
            hasPendingPermissions: monitor.pendingPermissions.isEmpty == false,
            hasActiveSessions: monitor.activeSessions.contains { $0.status == .busy },
            lastCompletion: monitor.lastCompletion
        )
    }

    // MARK: - Notch Width

    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return 180
        }
        return rightArea.minX - leftArea.maxX
    }

    private var pillWidth: CGFloat {
        max(notchWidth + 80, 300)
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
