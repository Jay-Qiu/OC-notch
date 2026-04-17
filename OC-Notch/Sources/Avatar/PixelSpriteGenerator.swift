import SpriteKit
import AppKit

/// Generates pixel-art sprite textures programmatically.
/// These are placeholder sprites — replace with real pixel art assets later.
enum PixelSpriteGenerator {

    /// Generate animation frame textures for a given avatar state.
    static func generateTextures(for state: AvatarState, size: CGSize) -> [SKTexture] {
        (0..<state.frameCount).map { frame in
            let image = renderFrame(state: state, frame: frame, size: size)
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            return texture
        }
    }

    // MARK: - Frame Rendering

    private static func renderFrame(state: AvatarState, frame: Int, size: CGSize) -> NSImage {
        let pixelSize: CGFloat = 3 // Each "pixel" is 3x3 points for visibility
        let gridW = Int(size.width / pixelSize)
        let gridH = Int(size.height / pixelSize)

        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let grid = generatePixelGrid(state: state, frame: frame, width: gridW, height: gridH)

        for y in 0..<gridH {
            for x in 0..<gridW {
                let color = grid[y][x]
                if color != .clear {
                    color.setFill()
                    NSRect(
                        x: CGFloat(x) * pixelSize,
                        y: CGFloat(gridH - 1 - y) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    ).fill()
                }
            }
        }

        image.unlockFocus()
        return image
    }

    // MARK: - Pixel Grid Generation

    private static func generatePixelGrid(state: AvatarState, frame: Int, width: Int, height: Int) -> [[NSColor]] {
        // Create an empty grid
        var grid = Array(repeating: Array(repeating: NSColor.clear, count: width), count: height)

        // Center coordinates
        let cx = width / 2
        let cy = height / 2

        switch state {
        case .idle:
            drawIdleFrame(grid: &grid, frame: frame, cx: cx, cy: cy)
        case .thinking:
            drawThinkingFrame(grid: &grid, frame: frame, cx: cx, cy: cy)
        case .alert:
            drawAlertFrame(grid: &grid, frame: frame, cx: cx, cy: cy)
        case .celebrate:
            drawCelebrateFrame(grid: &grid, frame: frame, cx: cx, cy: cy)
        }

        return grid
    }

    // MARK: - Idle: Gentle breathing bob

    private static func drawIdleFrame(grid: inout [[NSColor]], frame: Int, cx: Int, cy: Int) {
        let bob = frame % 2 == 0 ? 0 : 1 // Subtle vertical bob
        let body = NSColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1) // Green creature
        let eye = NSColor.white
        let pupil = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

        // Body (rounded rectangle-ish shape)
        for dy in -3...3 {
            let w = dy == -3 || dy == 3 ? 2 : (abs(dy) == 2 ? 3 : 4)
            for dx in -w...w {
                setPixel(grid: &grid, x: cx + dx, y: cy + dy + bob, color: body)
            }
        }

        // Eyes
        setPixel(grid: &grid, x: cx - 2, y: cy - 1 + bob, color: eye)
        setPixel(grid: &grid, x: cx + 2, y: cy - 1 + bob, color: eye)
        setPixel(grid: &grid, x: cx - 2, y: cy - 1 + bob, color: pupil) // Overlaid for blink frames
        if frame != 2 { // Blink on frame 2
            setPixel(grid: &grid, x: cx - 2, y: cy - 2 + bob, color: eye)
            setPixel(grid: &grid, x: cx + 2, y: cy - 2 + bob, color: eye)
            setPixel(grid: &grid, x: cx - 2, y: cy - 2 + bob, color: pupil)
            setPixel(grid: &grid, x: cx + 2, y: cy - 2 + bob, color: pupil)
        }

        // Mouth
        setPixel(grid: &grid, x: cx - 1, y: cy + 1 + bob, color: pupil)
        setPixel(grid: &grid, x: cx, y: cy + 1 + bob, color: pupil)
        setPixel(grid: &grid, x: cx + 1, y: cy + 1 + bob, color: pupil)

        // Feet
        setPixel(grid: &grid, x: cx - 2, y: cy + 4 + bob, color: body)
        setPixel(grid: &grid, x: cx + 2, y: cy + 4 + bob, color: body)
    }

    // MARK: - Thinking: Eyes dart side to side

    private static func drawThinkingFrame(grid: inout [[NSColor]], frame: Int, cx: Int, cy: Int) {
        let body = NSColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1) // Blue tint when thinking
        let eye = NSColor.white
        let pupil = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let eyeOffset = frame == 0 ? -1 : 1 // Eyes look left then right

        // Body
        for dy in -3...3 {
            let w = dy == -3 || dy == 3 ? 2 : (abs(dy) == 2 ? 3 : 4)
            for dx in -w...w {
                setPixel(grid: &grid, x: cx + dx, y: cy + dy, color: body)
            }
        }

        // Eyes with moving pupils
        setPixel(grid: &grid, x: cx - 2, y: cy - 2, color: eye)
        setPixel(grid: &grid, x: cx - 1, y: cy - 2, color: eye)
        setPixel(grid: &grid, x: cx + 1, y: cy - 2, color: eye)
        setPixel(grid: &grid, x: cx + 2, y: cy - 2, color: eye)
        setPixel(grid: &grid, x: cx - 2 + eyeOffset, y: cy - 2, color: pupil)
        setPixel(grid: &grid, x: cx + 2 + eyeOffset, y: cy - 2, color: pupil)

        // Thinking dots "..."
        let dotPhase = frame
        for i in 0..<3 {
            if i <= dotPhase {
                setPixel(grid: &grid, x: cx + 3 + i, y: cy - 4, color: NSColor.white.withAlphaComponent(0.8))
            }
        }
    }

    // MARK: - Alert: Jump + exclamation mark

    private static func drawAlertFrame(grid: inout [[NSColor]], frame: Int, cx: Int, cy: Int) {
        let body = NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1) // Orange alert
        let eye = NSColor.white
        let pupil = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let alert = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)

        // Jump arc: frames 0-2 go up, 3-5 come down
        let jumpOffset: Int
        switch frame {
        case 0: jumpOffset = 0
        case 1: jumpOffset = -2
        case 2: jumpOffset = -3
        case 3: jumpOffset = -3
        case 4: jumpOffset = -2
        default: jumpOffset = 0
        }

        // Body
        for dy in -3...3 {
            let w = dy == -3 || dy == 3 ? 2 : (abs(dy) == 2 ? 3 : 4)
            for dx in -w...w {
                setPixel(grid: &grid, x: cx + dx, y: cy + dy + jumpOffset, color: body)
            }
        }

        // Wide eyes (surprised)
        setPixel(grid: &grid, x: cx - 2, y: cy - 2 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx - 2, y: cy - 3 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx - 1, y: cy - 2 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx - 1, y: cy - 3 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx - 2, y: cy - 2 + jumpOffset, color: pupil)

        setPixel(grid: &grid, x: cx + 1, y: cy - 2 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx + 1, y: cy - 3 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx + 2, y: cy - 2 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx + 2, y: cy - 3 + jumpOffset, color: eye)
        setPixel(grid: &grid, x: cx + 2, y: cy - 2 + jumpOffset, color: pupil)

        // Open mouth
        setPixel(grid: &grid, x: cx, y: cy + 1 + jumpOffset, color: pupil)

        // Exclamation mark above head
        if frame >= 1 {
            setPixel(grid: &grid, x: cx, y: cy - 6 + jumpOffset, color: alert)
            setPixel(grid: &grid, x: cx, y: cy - 7 + jumpOffset, color: alert)
            setPixel(grid: &grid, x: cx, y: cy - 8 + jumpOffset, color: alert)
            setPixel(grid: &grid, x: cx, y: cy - 10 + jumpOffset, color: alert) // Dot
        }
    }

    // MARK: - Celebrate: Bounce + sparkles

    private static func drawCelebrateFrame(grid: inout [[NSColor]], frame: Int, cx: Int, cy: Int) {
        let body = NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1) // Gold celebration
        let eye = NSColor.white
        let pupil = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let sparkle = NSColor(red: 1.0, green: 1.0, blue: 0.5, alpha: 1)

        // Bounce: alternating up/down
        let bounce = frame % 2 == 0 ? 0 : -2

        // Sway: slight horizontal movement
        let sway = (frame / 2) % 2 == 0 ? -1 : 1

        // Body
        for dy in -3...3 {
            let w = dy == -3 || dy == 3 ? 2 : (abs(dy) == 2 ? 3 : 4)
            for dx in -w...w {
                setPixel(grid: &grid, x: cx + dx + sway, y: cy + dy + bounce, color: body)
            }
        }

        // Happy eyes (^_^)
        setPixel(grid: &grid, x: cx - 2 + sway, y: cy - 2 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx - 3 + sway, y: cy - 3 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx - 1 + sway, y: cy - 3 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx + 2 + sway, y: cy - 2 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx + 1 + sway, y: cy - 3 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx + 3 + sway, y: cy - 3 + bounce, color: pupil)

        // Wide smile
        setPixel(grid: &grid, x: cx - 2 + sway, y: cy + 1 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx - 1 + sway, y: cy + 2 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx + sway, y: cy + 2 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx + 1 + sway, y: cy + 2 + bounce, color: pupil)
        setPixel(grid: &grid, x: cx + 2 + sway, y: cy + 1 + bounce, color: pupil)

        // Sparkles at various positions, rotating
        let sparklePositions: [(Int, Int)] = [
            (-5, -5), (5, -4), (-4, -7), (6, -6), (0, -8), (-6, -3), (4, -8)
        ]
        for (i, pos) in sparklePositions.enumerated() {
            if (frame + i) % 3 == 0 {
                setPixel(grid: &grid, x: cx + pos.0, y: cy + pos.1, color: sparkle)
            }
        }

        // Arms up!
        setPixel(grid: &grid, x: cx - 5 + sway, y: cy - 2 + bounce, color: body)
        setPixel(grid: &grid, x: cx - 6 + sway, y: cy - 3 + bounce, color: body)
        setPixel(grid: &grid, x: cx + 5 + sway, y: cy - 2 + bounce, color: body)
        setPixel(grid: &grid, x: cx + 6 + sway, y: cy - 3 + bounce, color: body)
    }

    // MARK: - Helpers

    private static func setPixel(grid: inout [[NSColor]], x: Int, y: Int, color: NSColor) {
        guard y >= 0 && y < grid.count && x >= 0 && x < grid[0].count else { return }
        grid[y][x] = color
    }
}
