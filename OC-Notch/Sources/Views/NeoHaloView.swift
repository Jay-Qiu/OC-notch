import SwiftUI

enum NeoHaloState {
    case none
    case thinking
    case permission
    case question
}

struct NeoHaloOverlay: View {
    let state: NeoHaloState
    let cornerRadius: CGFloat
    /// When set, the `.thinking` halo is rendered as a centered shape of this
    /// size — typically the hardware notch dimensions — instead of overflowing
    /// the full pill bar.
    var thinkingNotchSize: CGSize? = nil

    var body: some View {
        Group {
            switch state {
            case .none:
                EmptyView()
            case .thinking:
                if let size = thinkingNotchSize {
                    ProgressingHalo(cornerRadius: cornerRadius)
                        .frame(width: size.width, height: size.height)
                } else {
                    ProgressingHalo(cornerRadius: cornerRadius)
                        .padding(-6)
                }
            case .permission:
                FlashingHalo(color: DS.Colors.accentOrange, cornerRadius: cornerRadius)
                    .padding(-6)
            case .question:
                SteadyHalo(color: DS.Colors.accentBlue, cornerRadius: cornerRadius)
                    .padding(-6)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ProgressingHalo: View {
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { (context: TimelineViewDefaultContext) in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6

            let head = phase
            let tail = max(0.0, head - 0.35)
            let stops: [Gradient.Stop] = [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: max(0.0, tail - 0.001)),
                .init(color: DS.Colors.accentGreen.opacity(0.0), location: tail),
                .init(color: DS.Colors.accentGreen, location: head),
                .init(color: DS.Colors.accentGreen.opacity(0.0), location: min(1.0, head + 0.001)),
                .init(color: .clear, location: 1.0)
            ]

            let gradient = LinearGradient(
                stops: stops,
                startPoint: .leading,
                endPoint: .trailing
            )

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 3)
                    .blur(radius: 4)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 1.2)
                    .blur(radius: 0.5)
            }
        }
    }
}

private struct FlashingHalo: View {
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { (context: TimelineViewDefaultContext) in
            let t = context.date.timeIntervalSinceReferenceDate
            let frequency = 2.2
            let raw = sin(t * 2 * .pi * frequency)
            let normalized = (raw + 1) / 2
            let intensity = 0.25 + normalized * 0.75

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(intensity), lineWidth: 3)
                    .blur(radius: 5 + intensity * 3)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(intensity), lineWidth: 1.2)
            }
        }
    }
}

private struct SteadyHalo: View {
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { (context: TimelineViewDefaultContext) in
            let t = context.date.timeIntervalSinceReferenceDate
            let frequency = 0.6
            let raw = sin(t * 2 * .pi * frequency)
            let normalized = (raw + 1) / 2
            let opacity = 0.85 + normalized * 0.15

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(opacity), lineWidth: 3)
                    .blur(radius: 4)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(opacity), lineWidth: 1.2)
            }
        }
    }
}
