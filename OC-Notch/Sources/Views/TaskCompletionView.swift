import SwiftUI

/// Shows a brief notification when an agent completes a task.
/// Auto-dismisses after 5s. Includes "Open" button to focus the terminal.
struct TaskCompletionView: View {
    let completion: TaskCompletionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(completion.sessionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()

                Button {
                    TerminalLauncher.activateTerminal()
                } label: {
                    HStack(spacing: 3) {
                        Text("Open")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if let summary = completion.summary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }

            if completion.filesChanged != nil || completion.additions != nil || completion.deletions != nil {
                HStack(spacing: 12) {
                    if let files = completion.filesChanged, files > 0 {
                        Label("\(files) files", systemImage: "doc")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let additions = completion.additions, additions > 0 {
                        Text("+\(additions)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if let deletions = completion.deletions, deletions > 0 {
                        Text("-\(deletions)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
