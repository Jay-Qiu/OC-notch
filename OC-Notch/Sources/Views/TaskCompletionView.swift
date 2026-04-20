import SwiftUI

/// Shows a brief notification when an agent completes a task.
/// Auto-dismisses after 5s. Includes "Open" button to focus the terminal.
struct TaskCompletionView: View {
    let completion: TaskCompletionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sectionSpacing) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Colors.accentGreen)
                Text(completion.sessionTitle)
                    .font(DS.Typography.title())
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()

                Button {
                    TerminalLauncher.activateTerminal()
                } label: {
                    HStack(spacing: 3) {
                        Text("Open")
                            .font(DS.Typography.caption())
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if let summary = completion.summary {
                Text(summary)
                    .font(DS.Typography.body())
                    .foregroundStyle(DS.Colors.textPrimary.opacity(0.8))
                    .lineLimit(2)
            }

            if completion.filesChanged != nil || completion.additions != nil || completion.deletions != nil {
                HStack(spacing: 12) {
                    if let files = completion.filesChanged, files > 0 {
                        Label("\(files) files", systemImage: "doc")
                            .font(DS.Typography.stats())
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    if let additions = completion.additions, additions > 0 {
                        Text("+\(additions)")
                            .font(DS.Typography.stats())
                            .foregroundStyle(DS.Colors.accentGreen)
                    }
                    if let deletions = completion.deletions, deletions > 0 {
                        Text("-\(deletions)")
                            .font(DS.Typography.stats())
                            .foregroundStyle(DS.Colors.accentRed)
                    }
                }
                .padding(.horizontal, DS.Spacing.sectionSpacing)
                .padding(.vertical, DS.Spacing.tightSpacing)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                        .fill(DS.Colors.elevatedSurface)
                )
            }
        }
        .dsCardBackground()
    }
}
