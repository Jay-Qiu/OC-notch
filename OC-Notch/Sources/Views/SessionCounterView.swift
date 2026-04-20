import SwiftUI

/// Displays the number of active OpenCode sessions to the right of the notch.
/// Tappable to toggle the session dropdown.
struct SessionCounterView: View {
    @Environment(SessionMonitorService.self) private var monitor
    let onTap: () -> Void

    private var hasActiveSessions: Bool {
        monitor.activeSessions.contains { $0.status == .busy }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.tightSpacing) {
                Circle()
                    .fill(hasActiveSessions ? DS.Colors.accentGreen : DS.Colors.textTertiary)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .fill(DS.Colors.accentGreen.opacity(0.4))
                            .frame(width: 12, height: 12)
                            .opacity(hasActiveSessions ? 1 : 0)
                            .scaleEffect(hasActiveSessions ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: hasActiveSessions)
                    )

                Text("\(monitor.activeSessions.count)")
                    .font(DS.Typography.counter())
                    .foregroundStyle(DS.Colors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(DS.Animations.snappy, value: monitor.activeSessions.count)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(DS.Colors.cardSurface)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(DS.Colors.separator, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
