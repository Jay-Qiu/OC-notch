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
            .padding(8)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - No Sessions

    private var noSessionsView: some View {
        HStack {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
            Text("No active sessions")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: OCSession) -> some View {
        Button {
            TerminalLauncher.activateTerminal()
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                // Status indicator dot
                Circle()
                    .fill(statusColor(for: session))
                    .frame(width: 6, height: 6)

                // Session title
                Text(session.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Project directory (short)
                Text(shortDirectory(session.directory))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Status label
                statusLabel(for: session)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Status

    private func statusColor(for session: OCSession) -> Color {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            return .red      // Waiting for input
        }
        switch session.status {
        case .busy:
            return .yellow    // Active / tool running
        case .retry:
            return .orange    // Retrying
        case .idle:
            return .green     // Idle
        }
    }

    @ViewBuilder
    private func statusLabel(for session: OCSession) -> some View {
        if monitor.pendingPermissions.contains(where: { $0.sessionID == session.id }) {
            Text("⏳")
                .font(.system(size: 10))
        } else {
            switch session.status {
            case .busy:
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            case .retry(_, _, _):
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            case .idle:
                EmptyView()
            }
        }
    }

    // MARK: - Helpers

    private func shortDirectory(_ path: String) -> String {
        // Extract last path component as project name
        let components = path.split(separator: "/")
        return components.last.map(String.init) ?? path
    }
}
