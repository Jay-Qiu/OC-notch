import SwiftUI

/// Dropdown list showing all active sessions with rich status cards.
struct SessionDropdownView: View {
    @Environment(SessionMonitorService.self) private var monitor
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.sectionSpacing) {
                if monitor.activeSessions.isEmpty {
                    noSessionsView
                } else {
                    ForEach(monitor.activeSessions) { session in
                        SessionRowButton(session: session, monitor: monitor, onDismiss: onDismiss)
                    }
                }
            }
            .padding(DS.Spacing.sectionSpacing)
        }
        .frame(maxHeight: 340)
    }

    // MARK: - No Sessions

    private var noSessionsView: some View {
        VStack(spacing: DS.Spacing.sectionSpacing) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.textTertiary)
            Text("No active sessions")
                .font(DS.Typography.body())
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.cardPadding)
    }
}

// MARK: - Session Row Button

private struct SessionRowButton: View {
    let session: OCSession
    let monitor: SessionMonitorService
    let onDismiss: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onDismiss()
            TerminalLauncher.activateTerminal(
                tab: monitor.terminalTabForSession(session.id),
                pid: monitor.pidForSession(session.id),
                directory: session.directory
            )
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sectionSpacing) {
                statusIndicator
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: DS.Spacing.elementSpacing) {
                    HStack {
                        Text(session.title)
                            .font(DS.Typography.body())
                            .foregroundStyle(DS.Colors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        statusBadge
                    }

                    HStack(spacing: DS.Spacing.tightSpacing) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Colors.textTertiary)

                        Text(shortDirectory(session.directory))
                            .font(DS.Typography.caption())
                            .foregroundStyle(DS.Colors.textTertiary)
                            .lineLimit(1)

                        Text("\u{00B7}")
                            .font(DS.Typography.caption())
                            .foregroundStyle(DS.Colors.textTertiary)

                        Text(relativeTime(session.timeUpdated))
                            .font(DS.Typography.caption())
                            .foregroundStyle(DS.Colors.textTertiary)
                    }

                    if let summary = session.summary,
                       summary.files > 0 || summary.additions > 0 || summary.deletions > 0 {
                        HStack(spacing: 10) {
                            if summary.files > 0 {
                                Label("\(summary.files) files", systemImage: "doc")
                                    .font(DS.Typography.stats())
                                    .foregroundStyle(DS.Colors.textSecondary)
                            }
                            if summary.additions > 0 {
                                Text("+\(summary.additions)")
                                    .font(DS.Typography.stats())
                                    .foregroundStyle(DS.Colors.accentGreen)
                            }
                            if summary.deletions > 0 {
                                Text("-\(summary.deletions)")
                                    .font(DS.Typography.stats())
                                    .foregroundStyle(DS.Colors.accentRed)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.sectionSpacing)
                        .padding(.vertical, DS.Spacing.tightSpacing)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radii.tiny, style: .continuous)
                                .fill(DS.Colors.elevatedSurface)
                        )
                    }
                }
            }
            .padding(DS.Spacing.cardPadding - 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.Radii.innerCard, style: .continuous)
                .fill(isHovered ? DS.Colors.cardSurfaceHover : DS.Colors.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radii.innerCard, style: .continuous)
                        .strokeBorder(
                            isHovered ? statusColor.opacity(0.25) : DS.Colors.separator,
                            lineWidth: isHovered ? 1 : 0.5
                        )
                )
                .shadow(
                    color: isHovered ? statusColor.opacity(0.15) : .clear,
                    radius: 8
                )
                .animation(DS.Animations.smooth, value: isHovered)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(DS.Animations.interactive, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        ZStack {
            // Pulse ring for busy sessions
            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 16, height: 16)
                .opacity(session.status == .busy ? 1 : 0)
                .scaleEffect(session.status == .busy ? 1.0 : 0.5)
                .animation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: session.status == .busy
                )

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            badgeCapsule(text: "Needs input", color: DS.Colors.accentRed, icon: "exclamationmark.circle")
        } else {
            switch session.status {
            case .busy:
                badgeCapsule(text: "Working", color: DS.Colors.accentYellow, icon: "play.fill")
            case .retry(_, _, _):
                badgeCapsule(text: "Retrying", color: DS.Colors.accentOrange, icon: "arrow.clockwise")
            case .idle:
                EmptyView()
            }
        }
    }

    private func badgeCapsule(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(DS.Typography.micro())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            return DS.Colors.accentRed
        }
        switch session.status {
        case .busy: return DS.Colors.accentYellow
        case .retry: return DS.Colors.accentOrange
        case .idle: return DS.Colors.accentGreen
        }
    }

    private func shortDirectory(_ path: String) -> String {
        let components = path.split(separator: "/")
        return components.last.map(String.init) ?? path
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
