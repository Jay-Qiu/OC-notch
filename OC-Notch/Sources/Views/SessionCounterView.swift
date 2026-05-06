import SwiftUI

/// Displays the number of active OpenCode sessions to the right of the notch.
/// Tappable to toggle the session dropdown.
struct SessionCounterView: View {
    @Environment(SessionMonitorService.self) private var monitor

    private var hasPendingQuestion: Bool {
        !monitor.pendingQuestions.isEmpty
    }

    private var hasActiveSessions: Bool {
        monitor.activeSessions.contains { $0.status == .busy }
    }

    /// Pending questions take priority over busy state — the user owes a reply
    /// even if other sessions are still working.
    private var accentColor: Color? {
        if hasPendingQuestion { return DS.Colors.accentBlue }
        if hasActiveSessions { return DS.Colors.accentGreen }
        return nil
    }

    @State private var isBreathing = false

    var body: some View {
        let accent = accentColor
        let isAnimating = accent != nil

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
                                accent.map { $0.opacity(isBreathing ? 0.6 : 0.2) } ?? DS.Colors.separator,
                                lineWidth: isAnimating ? 1 : 0.5
                            )
                    )
                    .scaleEffect(isAnimating && isBreathing ? 1.08 : 1.0)
                    .shadow(
                        color: accent.map { $0.opacity(isBreathing ? 0.3 : 0) } ?? .clear,
                        radius: isBreathing ? 6 : 0
                    )
            )
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isBreathing)
            .onChange(of: isAnimating) { _, animating in
                isBreathing = animating
            }
            .onAppear {
                isBreathing = isAnimating
            }
    }
}
