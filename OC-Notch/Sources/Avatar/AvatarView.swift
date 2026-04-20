import SwiftUI
import SpriteKit

/// SwiftUI wrapper for the SpriteKit avatar scene.
struct AvatarView: View {
    let scene: AvatarScene

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .frame(width: 36, height: 36)
            .background(.clear)
            .allowsHitTesting(false)
    }
}
