import SpriteKit

// MARK: - AvatarState

/// The visual states of the pixel avatar, each with its own animation.
enum AvatarState: Equatable {
    case idle       // Breathing/bobbing, 4 frames, 0.4s/frame
    case thinking   // Eyes moving, 2 frames, 0.3s/frame
    case alert      // Jump + exclamation, 6 frames, 0.15s/frame
    case celebrate  // Dance/jump, 8 frames, 0.12s/frame

    var frameCount: Int {
        switch self {
        case .idle: 4
        case .thinking: 2
        case .alert: 6
        case .celebrate: 8
        }
    }

    var frameDuration: TimeInterval {
        switch self {
        case .idle: 0.4
        case .thinking: 0.3
        case .alert: 0.15
        case .celebrate: 0.12
        }
    }
}

// MARK: - AvatarScene

/// SpriteKit scene that renders a pixel-art avatar with state-based animations.
/// Uses `filteringMode = .nearest` for crisp pixel-perfect rendering.
final class AvatarScene: SKScene {
    private let sprite: SKSpriteNode
    private var currentState: AvatarState = .idle

    /// Cache of generated textures per state
    private var textureCache: [AvatarState: [SKTexture]] = [AvatarState: [SKTexture]]()

    override init(size: CGSize) {
        sprite = SKSpriteNode()
        sprite.size = size
        super.init(size: size)

        backgroundColor = .clear
        scaleMode = .resizeFill

        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(sprite)

        // Generate all textures upfront
        for state in [AvatarState.idle, .thinking, .alert, .celebrate] {
            textureCache[state] = PixelSpriteGenerator.generateTextures(for: state, size: size)
        }

        // Start idle animation
        applyAnimation(for: .idle)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - State Management

    func setState(_ newState: AvatarState) {
        guard newState != currentState else { return }
        currentState = newState
        applyAnimation(for: newState)
    }

    private func applyAnimation(for state: AvatarState) {
        sprite.removeAllActions()

        guard let textures = textureCache[state], textures.isEmpty == false else { return }

        // Ensure pixel-perfect rendering
        for texture in textures {
            texture.filteringMode = .nearest
        }

        let animation = SKAction.animate(with: textures, timePerFrame: state.frameDuration)
        sprite.run(SKAction.repeatForever(animation))
    }
}
