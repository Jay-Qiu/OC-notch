import SwiftUI

/// Displays the number of active OpenCode sessions to the right of the notch.
/// Tappable to toggle the session dropdown.
struct SessionCounterView: View {
    @Environment(SessionMonitorService.self) private var monitor
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\(monitor.activeSessions.count)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: monitor.activeSessions.count)
        }
        .buttonStyle(.plain)
    }
}
