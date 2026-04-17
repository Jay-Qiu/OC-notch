import SwiftUI

/// Displays a permission request in the expanded notch area.
struct PermissionRequestView: View {
    let request: OCPermissionRequest
    @Environment(SessionMonitorService.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Session name + permission type
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

            // Command/action description
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

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .once) }
                } label: {
                    Label("Allow Once", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .always) }
                } label: {
                    Label("Always", systemImage: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .reject) }
                } label: {
                    Label("Reject", systemImage: "xmark")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
