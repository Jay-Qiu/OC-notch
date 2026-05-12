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
    var notchHardwareSize: CGSize? = nil
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
                ProgressingHalo(
                    color: DS.Colors.accentGreen,
                    cornerRadius: cornerRadius,
                    cycleSeconds: 1.8,
                    arcRatio: 0.35,
                    notchSize: notchHardwareSize,
                    coreLineWidth: 4.0,
                    midLineWidth: 8.0,
                    outerLineWidth: 14.0,
                    haloLineWidth: 20.0,
                    coreBlur: 0,
                    midBlur: 5,
                    outerBlur: 16,
                    haloBlur: 28
                )
            case .permission:
                FlashingHalo(
                    color: DS.Colors.accentOrange,
                    cornerRadius: cornerRadius,
                    frequency: 2.4,
                    minAlpha: 0.45,
                    maxAlpha: 1.0,
                    notchSize: notchHardwareSize,
                    coreLineWidth: 4.0,
                    midLineWidth: 8.0,
                    outerLineWidth: 14.0,
                    haloLineWidth: 20.0,
                    coreBlur: 0,
                    midBlur: 5,
                    outerBlur: 16,
                    haloBlur: 28
                )
            case .question:
                FlashingHalo(
                    color: DS.Colors.accentBlue,
                    cornerRadius: cornerRadius,
                    frequency: 1.4,
                    minAlpha: 0.35,
                    maxAlpha: 1.0,
                    notchSize: notchHardwareSize,
                    coreLineWidth: 4.0,
                    midLineWidth: 8.0,
                    outerLineWidth: 14.0,
                    haloLineWidth: 20.0,
                    coreBlur: 0,
                    midBlur: 5,
                    outerBlur: 16,
                    haloBlur: 28
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private func notchPath(canvasSize: CGSize, notchSize: CGSize?, cornerRadius: CGFloat, inset: CGFloat) -> (Path, CGFloat)? {
    let target = notchSize ?? canvasSize
    let originX = (canvasSize.width - target.width) / 2
    // Offset upward so the stroke center sits at ~y=4 in canvas space.
    // Combined with the .offset(y: -2) on the overlay, glow appears at ~y=2 on screen,
    // creating a natural taper at the top without a hard-clipped edge.
    let originY: CGFloat = -(inset - 4)
    // Compensate height so the bottom stays at the same absolute position
    let outer = CGRect(x: originX, y: originY, width: target.width, height: target.height - originY)
    let rect = outer.insetBy(dx: inset, dy: inset)
    guard rect.width > 0, rect.height > 0 else { return nil }

    let bottomRadius = min(max(0, cornerRadius - inset), min(rect.width, rect.height) / 2)
    var path = Path()

    // Start at top-left (sharp corner)
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))

    // Top edge to top-right (sharp corner)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

    // Right edge down to bottom-right corner
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))

    // Bottom-right corner (rounded)
    path.addArc(
        center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
        radius: bottomRadius,
        startAngle: .degrees(0),
        endAngle: .degrees(90),
        clockwise: false
    )

    // Bottom edge
    path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))

    // Bottom-left corner (rounded)
    path.addArc(
        center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
        radius: bottomRadius,
        startAngle: .degrees(90),
        endAngle: .degrees(180),
        clockwise: false
    )

    // Left edge back to start
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

    // Perimeter for dash animation
    let straightX = max(0, rect.width - 2 * bottomRadius)
    let straightY = max(0, rect.height - 2 * bottomRadius)
    let perim = 2 * straightX + 2 * straightY + 2 * .pi * bottomRadius
    return (path, perim)
}

private struct ProgressingHalo: View {
    let color: Color
    let cornerRadius: CGFloat
    let cycleSeconds: Double
    let arcRatio: Double
    let notchSize: CGSize?
    let coreLineWidth: CGFloat
    let midLineWidth: CGFloat
    let outerLineWidth: CGFloat
    let haloLineWidth: CGFloat
    let coreBlur: CGFloat
    let midBlur: CGFloat
    let outerBlur: CGFloat
    let haloBlur: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds
            haloFrame(phase: phase)
        }
    }

    @ViewBuilder
    private func haloFrame(phase: Double) -> some View {
        Canvas { ctx, size in
            let inset = haloLineWidth / 2
            guard let (path, perim) = notchPath(canvasSize: size, notchSize: notchSize, cornerRadius: cornerRadius, inset: inset),
                  perim > 0 else { return }
            let arc = perim * arcRatio
            let gap = max(0.001, perim - arc)
            let dashPhase = phase * perim

            let outlineStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            ctx.stroke(path, with: .color(color.opacity(0.25)), style: outlineStyle)

            let haloStyle = StrokeStyle(lineWidth: haloLineWidth, lineCap: .round, lineJoin: .round, dash: [arc, gap], dashPhase: dashPhase)
            let outerStyle = StrokeStyle(lineWidth: outerLineWidth, lineCap: .round, lineJoin: .round, dash: [arc, gap], dashPhase: dashPhase)
            let midStyle = StrokeStyle(lineWidth: midLineWidth, lineCap: .round, lineJoin: .round, dash: [arc, gap], dashPhase: dashPhase)
            let coreStyle = StrokeStyle(lineWidth: coreLineWidth, lineCap: .round, lineJoin: .round, dash: [arc, gap], dashPhase: dashPhase)

            ctx.drawLayer { l in
                l.addFilter(.blur(radius: haloBlur))
                l.stroke(path, with: .color(color.opacity(0.55)), style: haloStyle)
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: outerBlur))
                l.stroke(path, with: .color(color.opacity(0.85)), style: outerStyle)
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: midBlur))
                l.stroke(path, with: .color(color), style: midStyle)
            }
            if coreBlur > 0 {
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: coreBlur))
                    l.stroke(path, with: .color(.white.opacity(0.9)), style: coreStyle)
                }
            } else {
                ctx.stroke(path, with: .color(.white.opacity(0.9)), style: coreStyle)
            }
        }
    }
}

private struct FlashingHalo: View {
    let color: Color
    let cornerRadius: CGFloat
    let frequency: Double
    let minAlpha: Double
    let maxAlpha: Double
    let notchSize: CGSize?
    let coreLineWidth: CGFloat
    let midLineWidth: CGFloat
    let outerLineWidth: CGFloat
    let haloLineWidth: CGFloat
    let coreBlur: CGFloat
    let midBlur: CGFloat
    let outerBlur: CGFloat
    let haloBlur: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let raw = sin(t * 2 * .pi * frequency)
            let n = (raw + 1) / 2
            let alpha = minAlpha + n * (maxAlpha - minAlpha)
            haloFrame(alpha: alpha)
        }
    }

    @ViewBuilder
    private func haloFrame(alpha: Double) -> some View {
        Canvas { ctx, size in
            let inset = haloLineWidth / 2
            guard let (path, _) = notchPath(canvasSize: size, notchSize: notchSize, cornerRadius: cornerRadius, inset: inset) else { return }

            let outlineStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            ctx.stroke(path, with: .color(color.opacity(0.25)), style: outlineStyle)

            let haloStyle = StrokeStyle(lineWidth: haloLineWidth, lineCap: .round, lineJoin: .round)
            let outerStyle = StrokeStyle(lineWidth: outerLineWidth, lineCap: .round, lineJoin: .round)
            let midStyle = StrokeStyle(lineWidth: midLineWidth, lineCap: .round, lineJoin: .round)
            let coreStyle = StrokeStyle(lineWidth: coreLineWidth, lineCap: .round, lineJoin: .round)

            ctx.drawLayer { l in
                l.addFilter(.blur(radius: haloBlur))
                l.stroke(path, with: .color(color.opacity(alpha * 0.55)), style: haloStyle)
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: outerBlur))
                l.stroke(path, with: .color(color.opacity(alpha * 0.85)), style: outerStyle)
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: midBlur))
                l.stroke(path, with: .color(color.opacity(alpha)), style: midStyle)
            }
            if coreBlur > 0 {
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: coreBlur))
                    l.stroke(path, with: .color(.white.opacity(alpha * 0.9)), style: coreStyle)
                }
            } else {
                ctx.stroke(path, with: .color(.white.opacity(alpha * 0.9)), style: coreStyle)
            }
        }
    }
}
