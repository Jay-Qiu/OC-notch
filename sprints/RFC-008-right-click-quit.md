# RFC-008 — Right-Click Context Menu (Quit App)

**Sprint** : 4 (Semaine 7-8)
**Priorite** : P0
**Dependances** : RFC-001 (NotchPanel)
**References CDC** : CT-01 (ne pas voler le focus)

---

## Contexte

L'app OC-Notch fonctionne sans icone dock et sans menu bar. Aujourd'hui, le seul moyen de quitter l'app est via `⌘Q` (si l'app a le focus) ou via Activity Monitor / `kill`. C'est un probleme d'UX basique : l'utilisateur doit pouvoir fermer l'app facilement.

**Objectif** : Un right-click (clic droit) sur le notch affiche un menu contextuel avec au minimum l'option "Quitter OC-Notch".

## Decision technique

### NSMenu sur le NSPanel

Le `NotchPanel` (NSPanel) intercepte deja les mouse events. On ajoute un handler pour le right-click qui affiche un `NSMenu`.

```swift
// Dans NotchPanel ou le view controller associe
override func rightMouseDown(with event: NSEvent) {
    let menu = NSMenu()
    
    menu.addItem(withTitle: "A propos d'OC-Notch",
                 action: #selector(showAbout),
                 keyEquivalent: "")
    
    menu.addItem(.separator())
    
    menu.addItem(withTitle: "Chercher une mise a jour...",
                 action: #selector(checkForUpdates),
                 keyEquivalent: "")
    
    menu.addItem(.separator())
    
    menu.addItem(withTitle: "Quitter OC-Notch",
                 action: #selector(quitApp),
                 keyEquivalent: "q")
    
    NSMenu.popUpContextMenu(menu, with: event, for: self.contentView!)
}

@objc func quitApp() {
    NSApplication.shared.terminate(nil)
}
```

### Compatibilite avec le panel non-activating

`NSMenu.popUpContextMenu` fonctionne meme si `canBecomeKey = false`. Le menu contextuel est gere par le window server, pas par le key window. Pas de conflit avec la contrainte CT-01.

### Items du menu contextuel

| Item | Action | Sprint |
|------|--------|--------|
| A propos d'OC-Notch | Affiche version + credits | Sprint 4 |
| Chercher une mise a jour... | Declenche le check Sparkle (RFC-007) | Sprint 4 |
| Separateur | — | — |
| Quitter OC-Notch | `NSApp.terminate(nil)` | **Sprint 4 (P0)** |

### Layout

```
┌─────────────────────────────┐
│  [Avatar]  ███ NOTCH ███    │  ← right-click ici
├─────────────────────────────┤
│  A propos d'OC-Notch        │
│  ─────────────────────────  │
│  Chercher une mise a jour...│
│  ─────────────────────────  │
│  Quitter OC-Notch       ⌘Q │
└─────────────────────────────┘
```

### Zone de detection du right-click

Le right-click doit fonctionner sur toute la surface visible du notch panel :
- La barre permanente (avatar + compteur)
- La zone etendue (si permission/question affichee)

Si un formulaire de question/permission est affiche, le right-click sur les **boutons/options** ne doit PAS ouvrir le menu (pour eviter les clics accidentels). Le menu ne s'ouvre que sur les zones "neutres" (fond, barre du haut).

## Taches

- [ ] Implementer le handler `rightMouseDown` dans `NotchPanel`
- [ ] Creer le `NSMenu` avec les items : A propos, Mise a jour, Quitter
- [ ] Implementer l'action "Quitter" (`NSApp.terminate`)
- [ ] Implementer l'action "A propos" (mini fenetre avec version)
- [ ] Connecter "Chercher une mise a jour" au `SPUUpdater` (RFC-007)
- [ ] Tester que le right-click ne s'active PAS sur les boutons de permission/question
- [ ] Tester que le menu fonctionne sans focus steal (canBecomeKey = false)

## Criteres d'acceptation

1. Right-click sur le notch → menu contextuel apparait immediatement
2. "Quitter OC-Notch" → l'app se ferme proprement
3. Le menu ne vole PAS le focus de l'application en cours
4. Le right-click sur un bouton de permission/question n'ouvre PAS le menu
5. Le raccourci `⌘Q` est affiche dans le menu a cote de "Quitter"
