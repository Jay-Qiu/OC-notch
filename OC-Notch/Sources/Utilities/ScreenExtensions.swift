import AppKit

extension NSScreen {
    /// Returns the best screen to host the notch overlay.
    /// Priority: notched display → primary display (origin 0,0) → main → first available.
    static var targetScreen: NSScreen? {
        // 1. The screen with a physical notch (has auxiliary top areas)
        if let notched = screens.first(where: { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }) {
            return notched
        }
        // 2. The primary display (the one at origin 0,0 in global coords — set in System Settings > Displays)
        if let primary = screens.first(where: { $0.frame.origin == .zero }) {
            return primary
        }
        // 3. Fallback
        return main ?? screens.first
    }

    /// Whether this screen has a physical notch.
    var hasNotch: Bool {
        auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }
}
