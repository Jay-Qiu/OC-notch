# RFC-001 — Notch Window Shell

**Sprint** : 1 (Semaine 1-2)
**Priorité** : P0 — Fondation
**Dépendances** : Aucune
**Références CDC** : F-AV-01, CT-01, CT-02, CT-04

---

## Contexte

Toute l'app repose sur un overlay invisible positionné autour du notch matériel du MacBook. Ce ticket pose les fondations : une fenêtre non-activante qui reste au-dessus de tout, positionnée dynamiquement selon l'écran.

## Décision technique

### Stack
- **Swift 5.9+ / SwiftUI** — UI déclarative, animations natives
- **NSPanel** avec `.nonactivatingPanel` — ne vole pas le focus
- **Window level** : `NSWindow.Level.statusBar + 1` — au-dessus de la menu bar mais sous les alerts système

### Positionnement du notch

```swift
// macOS 12+ API pour détecter la zone safe autour du notch
guard let screen = NSScreen.main else { return }
let safeFrame = screen.safeAreaInsets // .top contient la hauteur du notch

// Alternative: auxiliaryTopLeftArea / auxiliaryTopRightArea (macOS 12+)
// Donne les rectangles utilisables de chaque côté du notch
let leftArea = screen.auxiliaryTopLeftArea   // zone gauche du notch
let rightArea = screen.auxiliaryTopRightArea // zone droite du notch
```

### Architecture window

```
NSPanel (non-activating, borderless)
├── contentView: NSHostingView<NotchShellView>
│   └── SwiftUI View hierarchy
│       ├── HStack
│       │   ├── SpriteView (gauche) — zone avatar
│       │   ├── Spacer (zone notch matériel)
│       │   └── SessionCounterView (droite)
│       └── ExpandableContentView (extension vers le bas)
```

### Contraintes implémentation

| Contrainte | Solution |
|------------|----------|
| Ne pas voler le focus | `NSPanel` + `.nonactivatingPanel` + `canBecomeKey = false` |
| Rester au-dessus | `level = .statusBar + 1` |
| Pas de shadow/chrome | `styleMask = [.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear` |
| Multi-taille notch | Lire `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` au launch + observer `NSApplication.didChangeScreenParametersNotification` |
| Launch at login | `SMAppService.mainApp` (macOS 13+) ou Login Items |

## Tâches

- [ ] Créer projet Xcode macOS App (SwiftUI lifecycle)
- [ ] Implémenter `NotchPanel` : NSPanel subclass non-activating, borderless, transparent
- [ ] Positionner dynamiquement autour du notch via `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`
- [ ] Observer les changements d'écran (branchement externe, changement résolution)
- [ ] Créer `NotchShellView` : layout HStack avec zones gauche/droite et spacer central
- [ ] Tester sur MacBook Pro 14" et 16"
- [ ] Fallback graceful si pas de notch (écran externe)

## Critères d'acceptation

1. Fenêtre transparente visible autour du notch sans voler le focus
2. Click-through sur la zone du notch matériel
3. Repositionnement automatique si changement d'écran
4. CPU < 0.5% au repos (pas de timer actif, juste idle)

## Risques

- `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` retournent `nil` sur écran sans notch → fallback requis
- Certains window managers tiers (Rectangle, Magnet) peuvent interférer → tester compatibilité
