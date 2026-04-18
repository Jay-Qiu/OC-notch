import SwiftUI

struct PermissionRequestView: View {
    let request: OCPermissionRequest
    @Environment(SessionMonitorService.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(request.sessionTitle ?? request.sessionID)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(request.permission)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let description = request.displayDescription {
                Text(description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .once) }
                } label: {
                    HStack(spacing: 4) {
                        Label("Allow Once", systemImage: "checkmark")
                        shortcutBadge("⌘Y")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut("y", modifiers: .command)

                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .always) }
                } label: {
                    HStack(spacing: 4) {
                        Label("Always", systemImage: "checkmark.circle")
                        shortcutBadge("⌘A")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("a", modifiers: .command)

                Spacer()

                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .reject) }
                } label: {
                    HStack(spacing: 4) {
                        Label("Reject", systemImage: "xmark")
                        shortcutBadge("⌘N")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
