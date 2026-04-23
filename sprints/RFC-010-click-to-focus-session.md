# RFC-010 — Click-to-Focus : Redirection vers la Session Source

**Sprint** : 4 (Semaine 7-8)
**Priorite** : P1
**Dependances** : RFC-009 (Multi-Session Queue), RFC-006 (Session Dropdown)
**References CDC** : F-NT-04 (bouton Ouvrir terminal)

---

## Contexte

Quand le notch affiche une question ou une permission request, l'utilisateur peut vouloir voir le contexte complet dans le terminal avant de repondre. Aujourd'hui, il doit manuellement trouver et ouvrir le bon terminal.

**Objectif** : Si l'utilisateur clique sur la zone du notch etendu mais **pas sur un bouton de reponse**, l'app focus/ouvre le terminal de la session qui pose la question. Cela permet de consulter le contexte avant de repondre.

## Decision technique

### Zone de detection

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 sessions]   │  ← clic ici = toggle dropdown (existant)
├──────────────────────────────────────────┤
│  ❓ api-refactor                          │  ← CLIC ICI = focus terminal ✓
│                                          │
│  "Which testing framework to use?"       │  ← CLIC ICI = focus terminal ✓
│  ┌─────────┐ ┌────────┐ ┌──────────┐   │
│  │ vitest  │ │ jest   │ │ mocha    │   │  ← CLIC ICI = selectionner option (existant)
│  └─────────┘ └────────┘ └──────────┘   │
│                                          │
│  Question 1/3  •  +1 session en attente  │  ← CLIC ICI = focus terminal ✓
└──────────────────────────────────────────┘
```

**Regle** : Tout clic dans la zone etendue qui n'est PAS sur un element interactif (bouton, option, lien) → focus le terminal de la session active.

### Implementation

```swift
// Dans la vue de question/permission etendue
struct InteractionContentView: View {
    let sessionID: SessionID
    @Environment(TerminalLauncher.self) var launcher
    
    var body: some View {
        VStack {
            // ... contenu de la question ...
        }
        .contentShape(Rectangle())  // Toute la zone est cliquable
        .onTapGesture {
            launcher.focusTerminal(for: sessionID)
        }
        // Les boutons internes ont leur propre onTapGesture
        // qui consomme l'event AVANT qu'il ne remonte au parent
    }
}
```

### Propagation des events

SwiftUI gere naturellement la priorite des gesture recognizers :
- Les boutons/options ont des tap handlers specifiques → ils consomment l'event
- Le `onTapGesture` sur le conteneur parent ne se declenche que si aucun enfant ne l'a consomme
- Pas besoin de logique custom de hit-testing

### Focus terminal : reutilisation de la logique RFC-005

La logique de focus terminal existe deja dans `TerminalLauncher` (RFC-005, bouton "Ouvrir") :
1. Identifier l'app terminal (Terminal.app, iTerm2, Warp, etc.) via le PID du process OpenCode
2. Activer l'app terminal via `NSRunningApplication.activate`
3. Si multi-fenetre/tab : identifier la bonne fenetre par le titre ou le TTY

Pas de nouvelle logique a creer — on reutilise `TerminalLauncher.focusTerminal(for:)`.

### Feedback visuel au clic

Pour indiquer que la zone est cliquable, ajouter :
- Curseur `pointingHand` au survol de la zone (hors boutons)
- Flash subtil de highlight au clic (opacity 0.7 pendant 100ms)

```swift
.onHover { hovering in
    if hovering {
        NSCursor.pointingHand.push()
    } else {
        NSCursor.pop()
    }
}
```

## Taches

- [ ] Ajouter `onTapGesture` sur le conteneur de la vue question/permission
- [ ] Connecter au `TerminalLauncher.focusTerminal(for: sessionID)`
- [ ] Verifier que les boutons de reponse consomment l'event (pas de double action)
- [ ] Ajouter le curseur `pointingHand` au survol de la zone cliquable
- [ ] Ajouter le feedback visuel au clic (flash highlight)
- [ ] Tester : clic sur le texte de la question → terminal se focus
- [ ] Tester : clic sur un bouton de reponse → reponse envoyee, terminal ne se focus PAS
- [ ] Tester avec iTerm2, Terminal.app, Warp — le bon terminal/tab se focus

## Criteres d'acceptation

1. Clic sur la zone "neutre" du notch etendu → le terminal de la session active se focus en < 500ms
2. Clic sur un bouton de reponse → la reponse est envoyee normalement, PAS de focus terminal
3. Le curseur change en `pointingHand` au survol de la zone cliquable
4. Fonctionne avec les terminaux supportes (Terminal.app, iTerm2, Warp)
5. Apres le focus terminal, le notch reste visible avec la question (l'utilisateur peut revenir repondre)
