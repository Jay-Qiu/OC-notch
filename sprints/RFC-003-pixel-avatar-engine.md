# RFC-003 — Pixel Avatar Engine

**Sprint** : 2 (Semaine 3-4)
**Priorité** : P0
**Dépendances** : RFC-001 (NotchPanel)
**Références CDC** : F-AV-01, F-AV-02, F-AV-03

---

## Contexte

L'avatar pixelisé à gauche du notch est l'identité visuelle de l'app. Doit être net (pixel-perfect), animé, et réactif à l'état des agents.

## Décision technique

### SpriteKit dans SwiftUI (via SpriteView)

SpriteKit est préférable à du SwiftUI pur pour les sprites car :
- `SKTexture.filteringMode = .nearest` → rendu pixel-perfect sans anti-aliasing
- `SKAction.animate(with:timePerFrame:)` → animation de frames native
- Gestion d'atlas de sprites optimisée
- Intégration SwiftUI via `SpriteView`

### Architecture

```swift
// Sprite sheet: PNG avec frames alignées horizontalement
// Chaque état = une ligne dans le sprite sheet

enum AvatarState {
    case idle       // respiration/rebond, 4 frames, 0.4s/frame
    case thinking   // yeux qui bougent, 2 frames, 0.3s/frame
    case alert      // sursaut + exclamation, 6 frames, 0.15s/frame
    case celebrate  // danse/jump, 8 frames, 0.12s/frame
}

class AvatarScene: SKScene {
    let sprite: SKSpriteNode
    var currentState: AvatarState = .idle
    
    func setState(_ state: AvatarState) {
        sprite.removeAllActions()
        let textures = loadTextures(for: state)
        let animation = SKAction.animate(with: textures, timePerFrame: state.frameDuration)
        sprite.run(SKAction.repeatForever(animation))
    }
}
```

### Sprite sheet format

```
sprite_idle.png      → 4 frames × 48px = 192×48 PNG
sprite_thinking.png  → 2 frames × 48px = 96×48 PNG
sprite_alert.png     → 6 frames × 48px = 288×48 PNG
sprite_celebrate.png → 8 frames × 48px = 384×48 PNG
```

Rendu sans lissage :
```swift
texture.filteringMode = .nearest  // critical: pixel-perfect
sprite.texture?.filteringMode = .nearest
```

### Intégration SwiftUI

```swift
struct AvatarView: View {
    let scene: AvatarScene
    
    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .frame(width: 48, height: 48)
            .background(.clear)
    }
}
```

### Transitions d'état

```
Session monitor events → AvatarStateManager → AvatarScene

Mapping:
- Toutes sessions idle          → .idle
- ≥1 session active (tool running) → .thinking
- Permission request pending     → .alert
- Tâche vient de se terminer     → .celebrate (5s) → .idle
```

## Tâches

- [ ] Créer les sprite sheets pixel-art (4 états, style pixel 48x48) — placeholder art d'abord
- [ ] Implémenter `AvatarScene` (SKScene) avec `filteringMode = .nearest`
- [ ] Implémenter le state machine des animations (idle/thinking/alert/celebrate)
- [ ] Intégrer dans `NotchShellView` via `SpriteView`
- [ ] Connecter au `SessionMonitorService` pour transitions automatiques
- [ ] Tester : transition fluide entre états, pas de flash/glitch

## Critères d'acceptation

1. Sprite 48x48 rendu net, sans flou/anti-aliasing
2. Animation idle boucle smooth
3. Transition vers alert en < 100ms quand permission request arrive
4. Celebration se joue et revient à idle automatiquement
5. Fond transparent (intégration notch seamless)
