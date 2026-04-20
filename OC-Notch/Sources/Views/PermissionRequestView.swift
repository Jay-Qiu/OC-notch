import SwiftUI

struct PermissionRequestView: View {
    let request: OCPermissionRequest
    @Environment(SessionMonitorService.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.cardInnerSpacing) {
            HStack(spacing: DS.Spacing.sectionSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Colors.accentOrange)
                Text(request.sessionTitle ?? request.sessionID)
                    .font(DS.Typography.title())
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                Text(request.permission)
                    .font(DS.Typography.caption())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DS.Colors.elevatedSurface)
                    )
            }

            if let description = request.displayDescription {
                Text(description)
                    .font(DS.Typography.bodyMono())
                    .foregroundStyle(DS.Colors.textPrimary.opacity(0.9))
                    .lineLimit(3)
                    .dsElevatedSurface()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: DS.Spacing.sectionSpacing) {
                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .once) }
                } label: {
                    HStack(spacing: DS.Spacing.tightSpacing) {
                        Label("Allow Once", systemImage: "checkmark")
                        Text("⌘Y").dsShortcutBadge()
                    }
                    .font(DS.Typography.caption())
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.accentGreen)
                .keyboardShortcut("y", modifiers: .command)

                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .always) }
                } label: {
                    HStack(spacing: DS.Spacing.tightSpacing) {
                        Label("Always", systemImage: "checkmark.circle")
                        Text("⌘A").dsShortcutBadge()
                    }
                    .font(DS.Typography.caption())
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("a", modifiers: .command)

                Spacer()

                Button {
                    Task { await monitor.replyPermission(requestID: request.id, reply: .reject) }
                } label: {
                    HStack(spacing: DS.Spacing.tightSpacing) {
                        Label("Reject", systemImage: "xmark")
                        Text("⌘N").dsShortcutBadge()
                    }
                    .font(DS.Typography.caption())
                }
                .buttonStyle(.bordered)
                .tint(DS.Colors.accentRed)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .dsCardBackground()
    }
}
