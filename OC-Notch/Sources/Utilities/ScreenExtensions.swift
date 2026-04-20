import AppKit
import CoreGraphics
import os.log

private let scaleLog = Logger(subsystem: "com.oc-notch", category: "DisplayScale")

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

    /// Ratio of the current logical resolution to the native/"Default" resolution.
    /// Returns 1.0 at "Default", > 1.0 at "More Space", < 1.0 at "Larger Text".
    var displayScaleFactor: CGFloat {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return 1.0
        }

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(screenNumber, options) as? [CGDisplayMode] else {
            return 1.0
        }

        // kDisplayModeNativeFlag (0x02000000) from IOGraphicsTypes.h identifies the
        // mode whose rendered resolution matches the physical display panel.
        let nativeFlag: UInt32 = 0x02000000
        let nativeModes = modes.filter { ($0.ioFlags & nativeFlag) != 0 && $0.pixelWidth > $0.width }

        // Pick the native mode closest to the physical panel resolution (highest pixelWidth).
        guard let nativeMode = nativeModes.max(by: { $0.pixelWidth < $1.pixelWidth }) else {
            scaleLog.warning("No native mode found among \(modes.count, privacy: .public) modes. screen=\(self.frame.width, privacy: .public)x\(self.frame.height, privacy: .public)")
            return 1.0
        }

        let nativeLogicalWidth = CGFloat(nativeMode.width)
        guard nativeLogicalWidth > 0 else { return 1.0 }

        let scale = frame.width / nativeLogicalWidth
        scaleLog.debug("scale=\(scale, privacy: .public) screen=\(self.frame.width, privacy: .public)x\(self.frame.height, privacy: .public) native=\(nativeLogicalWidth, privacy: .public) auxH=\(self.auxiliaryTopLeftArea?.height ?? -1, privacy: .public)")
        return scale
    }
}
