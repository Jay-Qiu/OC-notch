import SwiftUI

// MARK: - Design System (Dynamic Island–inspired)

/// Centralized design tokens for the OC-notch UI.
/// Inspired by iPhone Dynamic Island: dark pill background, fluid spring animations,
/// glass material depth, and subtle glow effects.
enum DS {

    // MARK: - Colors

    enum Colors {
        /// Primary pill/card background — deep black to blend with notch hardware
        static let pillBackground = Color.black
        /// Card surface — slightly lighter than pill for depth layering
        static let cardSurface = Color.white.opacity(0.06)
        /// Card surface on hover
        static let cardSurfaceHover = Color.white.opacity(0.10)
        /// Elevated surface for code blocks, descriptions
        static let elevatedSurface = Color.white.opacity(0.08)
        /// Elevated surface hover
        static let elevatedSurfaceHover = Color.white.opacity(0.14)

        /// Primary text
        static let textPrimary = Color.white
        /// Secondary text
        static let textSecondary = Color.white.opacity(0.55)
        /// Tertiary text (timestamps, hints)
        static let textTertiary = Color.white.opacity(0.35)

        /// Accent colors
        static let accentGreen = Color(red: 0.30, green: 0.85, blue: 0.45)
        static let accentOrange = Color(red: 1.0, green: 0.62, blue: 0.22)
        static let accentRed = Color(red: 1.0, green: 0.35, blue: 0.35)
        static let accentBlue = Color(red: 0.35, green: 0.60, blue: 1.0)
        static let accentYellow = Color(red: 1.0, green: 0.82, blue: 0.28)

        /// Separator
        static let separator = Color.white.opacity(0.08)

        /// Glow colors for hover / active states
        static let glowSubtle = Color.white.opacity(0.04)
        static let glowActive = Color.white.opacity(0.08)
    }

    // MARK: - Typography

    enum Typography {
        /// Title in expanded cards (session name, permission header)
        static func title() -> Font { .system(size: 13, weight: .semibold) }
        /// Body text (descriptions, summaries)
        static func body() -> Font { .system(size: 12) }
        /// Body monospaced (code snippets, file paths)
        static func bodyMono() -> Font { .system(size: 11, design: .monospaced) }
        /// Caption (secondary info, timestamps)
        static func caption() -> Font { .system(size: 10, weight: .medium) }
        /// Micro (keyboard shortcuts, pagination)
        static func micro() -> Font { .system(size: 9, weight: .medium, design: .rounded) }
        /// Counter (session count in pill)
        static func counter() -> Font { .system(size: 13, weight: .bold, design: .rounded) }
        /// Stats (file counts, additions/deletions)
        static func stats() -> Font { .system(size: 10, weight: .medium, design: .monospaced) }
    }

    // MARK: - Corner Radii

    enum Radii {
        /// Expanded card outer corners (top)
        static let expandedTop: CGFloat = 19
        /// Expanded card outer corners (bottom)
        static let expandedBottom: CGFloat = 24
        /// Compact/collapsed pill corners (top)
        static let compactTop: CGFloat = 6
        /// Compact/collapsed pill corners (bottom)
        static let compactBottom: CGFloat = 14
        /// Inner card / code block corners
        static let innerCard: CGFloat = 10
        /// Small element corners (badges, buttons)
        static let small: CGFloat = 6
        /// Tiny element corners (shortcut badges)
        static let tiny: CGFloat = 4
    }

    // MARK: - Spacing

    enum Spacing {
        static let cardPadding: CGFloat = 14
        static let cardInnerSpacing: CGFloat = 10
        static let sectionSpacing: CGFloat = 8
        static let elementSpacing: CGFloat = 6
        static let tightSpacing: CGFloat = 4
    }

    // MARK: - Animations

    enum Animations {
        /// Primary open animation — bouncy, personality-driven
        static let open = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
        /// Close animation — smooth, slightly damped
        static let close = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
        /// Interactive spring for hover/press states
        static let interactive = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
        /// Snappy for quick state changes (counter updates, dot transitions)
        static let snappy = Animation.snappy(duration: 0.35)
        /// Smooth for subtle transitions (opacity, glow)
        static let smooth = Animation.smooth(duration: 0.3)
        /// Content swap animation duration
        static let contentSwap = Animation.bouncy(duration: 0.4)
    }

    // MARK: - Shadows

    enum Shadows {
        /// Expanded card shadow — lifts the island above content
        static func expanded() -> some View {
            Color.black.opacity(0.7).blur(radius: 6)
        }

        /// Shadow modifier for expanded state
        static let expandedRadius: CGFloat = 8
        static let expandedOpacity: Double = 0.7
        static let expandedY: CGFloat = 4

        /// Compact shadow — subtle
        static let compactRadius: CGFloat = 4
        static let compactOpacity: Double = 0.3
    }

    // MARK: - Blur

    enum Blur {
        /// Content crossfade blur intensity
        static let contentTransition: CGFloat = 10
    }
}

// MARK: - Blur Transition (Dynamic Island style)

/// Custom blur transition for content swaps — inspired by DynamicNotchKit.
struct BlurModifier: ViewModifier {
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: intensity)
    }
}

extension AnyTransition {
    /// Blur + opacity transition for content crossfade
    static func blurFade(intensity: CGFloat = DS.Blur.contentTransition) -> AnyTransition {
        .modifier(
            active: BlurModifier(intensity: intensity),
            identity: BlurModifier(intensity: 0)
        )
        .combined(with: .opacity)
    }

    /// Blur + scale + opacity (full Dynamic Island feel)
    static func dynamicIsland(anchor: UnitPoint = .center) -> AnyTransition {
        .modifier(
            active: BlurModifier(intensity: DS.Blur.contentTransition),
            identity: BlurModifier(intensity: 0)
        )
        .combined(with: .scale(scale: 0.92, anchor: anchor))
        .combined(with: .opacity)
    }
}

// MARK: - View Extensions

extension View {
    /// Standard card background with Dynamic Island styling
    func dsCardBackground() -> some View {
        self
            .padding(DS.Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radii.innerCard, style: .continuous)
                    .fill(DS.Colors.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radii.innerCard, style: .continuous)
                            .strokeBorder(DS.Colors.separator, lineWidth: 0.5)
                    )
            )
    }

    /// Elevated surface (code blocks, descriptions)
    func dsElevatedSurface() -> some View {
        self
            .padding(DS.Spacing.sectionSpacing)
            .background(
                RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                    .fill(DS.Colors.elevatedSurface)
            )
    }

    /// Keyboard shortcut badge
    func dsShortcutBadge() -> some View {
        self
            .font(DS.Typography.micro())
            .foregroundStyle(DS.Colors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radii.tiny, style: .continuous)
                    .fill(DS.Colors.elevatedSurface)
            )
    }
}
