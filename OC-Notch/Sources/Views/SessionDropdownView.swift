import SwiftUI

/// Dropdown list showing all active sessions with status indicators.
struct SessionDropdownView: View {
    @Environment(SessionMonitorService.self) private var monitor
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if monitor.activeSessions.isEmpty {
                    noSessionsView
                } else {
                    ForEach(monitor.activeSessions) { session in
                        sessionRow(session)
                    }
                }
            }
            .padding(DS.Spacing.sectionSpacing)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - No Sessions

    private var noSessionsView: some View {
        HStack(spacing: DS.Spacing.sectionSpacing) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(DS.Colors.textTertiary)
            Text("No active sessions")
                .font(DS.Typography.body())
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(.vertical, DS.Spacing.sectionSpacing)
        .padding(.horizontal, DS.Spacing.tightSpacing)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: OCSession) -> some View {
        SessionRowButton(session: session, monitor: monitor, onDismiss: onDismiss)
    }

    // MARK: - Status

    private func statusColor(for session: OCSession) -> Color {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            return DS.Colors.accentRed
        }
        switch session.status {
        case .busy:
            return DS.Colors.accentYellow
        case .retry:
            return DS.Colors.accentOrange
        case .idle:
            return DS.Colors.accentGreen
        }
    }

    // MARK: - Helpers

    private func shortDirectory(_ path: String) -> String {
        let components = path.split(separator: "/")
        return components.last.map(String.init) ?? path
    }
}

// MARK: - Session Row Button (extracted for hover state)

private struct SessionRowButton: View {
    let session: OCSession
    let monitor: SessionMonitorService
    let onDismiss: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            TerminalLauncher.activateTerminal(directory: session.directory)
            onDismiss()
        } label: {
            HStack(spacing: DS.Spacing.sectionSpacing) {
                // Animated status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .fill(statusColor.opacity(0.4))
                            .frame(width: 12, height: 12)
                            .opacity(session.status == .busy ? 1 : 0)
                            .scaleEffect(session.status == .busy ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: session.status == .busy)
                    )

                Text(session.title)
                    .font(DS.Typography.caption())
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(shortDirectory(session.directory))
                    .font(DS.Typography.caption())
                    .foregroundStyle(DS.Colors.textTertiary)
                    .lineLimit(1)

                statusLabel
            }
            .padding(.vertical, DS.Spacing.elementSpacing)
            .padding(.horizontal, DS.Spacing.sectionSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                .fill(isHovered ? DS.Colors.cardSurfaceHover : DS.Colors.cardSurface)
                .animation(DS.Animations.smooth, value: isHovered)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusColor: Color {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            return DS.Colors.accentRed
        }
        switch session.status {
        case .busy:
            return DS.Colors.accentYellow
        case .retry:
            return DS.Colors.accentOrange
        case .idle:
            return DS.Colors.accentGreen
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            Text("⏳")
                .font(DS.Typography.caption())
        } else {
            switch session.status {
            case .busy:
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.Colors.accentYellow)
            case .retry(_, _, _):
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8))
                    .foregroundStyle(DS.Colors.accentOrange)
            case .idle:
                EmptyView()
            }
        }
    }

    private func shortDirectory(_ path: String) -> String {
        let components = path.split(separator: "/")
        return components.last.map(String.init) ?? path
    }
}
