import SwiftUI

/// Displays the number of active OpenCode sessions to the right of the notch.
/// Tappable to toggle the session dropdown.
struct SessionCounterView: View {
    @Environment(SessionMonitorService.self) private var monitor

    private var hasActiveSessions: Bool {
        monitor.activeSessions.contains { $0.status == .busy }
    }

    @State private var isBreathing = false

    var body: some View {
        Text("\(monitor.activeSessions.count)")
            .font(DS.Typography.counter())
            .foregroundStyle(DS.Colors.textPrimary)
            .contentTransition(.numericText())
            .animation(DS.Animations.snappy, value: monitor.activeSessions.count)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(DS.Colors.cardSurface)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                hasActiveSessions ? DS.Colors.accentGreen.opacity(isBreathing ? 0.6 : 0.2) : DS.Colors.separator,
                                lineWidth: hasActiveSessions ? 1 : 0.5
                            )
                    )
                    .scaleEffect(hasActiveSessions && isBreathing ? 1.08 : 1.0)
                    .shadow(
                        color: hasActiveSessions ? DS.Colors.accentGreen.opacity(isBreathing ? 0.3 : 0) : .clear,
                        radius: isBreathing ? 6 : 0
                    )
            )
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isBreathing)
            .onChange(of: hasActiveSessions) { _, active in
                isBreathing = active
            }
            .onAppear {
                isBreathing = hasActiveSessions
            }
    }
}
