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
    /// When set, the halo is rendered as a centered shape of this size —
    /// typically the hardware notch dimensions — instead of overflowing the
    /// full pill bar. Used by states (`thinking`, `question`) where the halo
    /// should hug the actual notch outline.
    var notchHardwareSize: CGSize? = nil
    /// Alias for compatibility with call sites using `notchSize`.
    var notchSize: CGSize? {
        get { notchHardwareSize }
    }

    init(state: NeoHaloState, cornerRadius: CGFloat, notchHardwareSize: CGSize? = nil, notchSize: CGSize? = nil) {
        self.state = state
        self.cornerRadius = cornerRadius
        self.notchHardwareSize = notchHardwareSize ?? notchSize
    }

    var body: some View {
        Group {
            switch state {
            case .none:
                EmptyView()
            case .thinking:
                if let size = notchHardwareSize {
                    ProgressingHalo(
                        cornerRadius: cornerRadius,
                        color: DS.Colors.accentGreen,
                        cycleSeconds: 1.6
                    )
                    .frame(width: size.width, height: size.height)
                } else {
                    ProgressingHalo(
                        cornerRadius: cornerRadius,
                        color: DS.Colors.accentGreen,
                        cycleSeconds: 1.6
                    )
                    .padding(-6)
                }
            case .permission:
                FlashingHalo(color: DS.Colors.accentOrange, cornerRadius: cornerRadius)
                    .padding(-6)
            case .question:
                if let size = notchHardwareSize {
                    ProgressingHalo(
                        cornerRadius: cornerRadius,
                        color: DS.Colors.accentBlue,
                        cycleSeconds: 2.4
                    )
                    .frame(width: size.width, height: size.height)
                } else {
                    ProgressingHalo(
                        cornerRadius: cornerRadius,
                        color: DS.Colors.accentBlue,
                        cycleSeconds: 2.4
                    )
                    .padding(-6)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ProgressingHalo: View {
    let cornerRadius: CGFloat
    let color: Color
    let cycleSeconds: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds

            let head = phase
            let tail = max(0.0, head - 0.35)
            let stops: [Gradient.Stop] = [
                Gradient.Stop(color: .clear, location: 0.0),
                Gradient.Stop(color: .clear, location: max(0.0, tail - 0.001)),
                Gradient.Stop(color: color.opacity(0.0), location: tail),
                Gradient.Stop(color: color, location: head),
                Gradient.Stop(color: color.opacity(0.0), location: min(1.0, head + 0.001)),
                Gradient.Stop(color: .clear, location: 1.0)
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
        TimelineView(.animation) { context in
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
