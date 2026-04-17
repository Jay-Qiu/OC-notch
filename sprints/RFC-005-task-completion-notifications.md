# RFC-005 — Task Completion Notifications

**Sprint** : 3 (Semaine 5-6)
**Priorité** : P0
**Dépendances** : RFC-001, RFC-002, RFC-003
**Références CDC** : F-NT-01 → F-NT-04

---

## Contexte

Quand un agent finit une tâche, le notch s'étend brièvement pour afficher un résumé. Le Pokémon célèbre. Auto-dismiss après 5 secondes.

## Détection de complétion

### Heuristique multi-signaux

```swift
class CompletionDetector {
    // Signal 1: Todos tous complétés
    // Quand le dernier todo passe à "completed" → tâche terminée
    func checkTodoCompletion(todos: [OCTodo]) -> Bool {
        !todos.isEmpty && todos.allSatisfy { $0.status == "completed" }
    }
    
    // Signal 2: Session idle après activité
    // Pas de message.part.updated depuis 10s après un message assistant
    func checkIdleAfterActivity(lastPartUpdate: Date) -> Bool {
        Date().timeIntervalSince(lastPartUpdate) > 10
    }
    
    // Signal 3: Session summary changed
    // summary_additions/deletions/files deviennent non-nil → travail terminé
    func checkSummaryAppeared(session: OCSession) -> Bool {
        session.summaryFiles != nil
    }
}
```

### Résumé de tâche

Source du résumé :
1. **Titre de session** — toujours dispo
2. **Dernier todo complété** — description de la dernière tâche
3. **Summary diffs** — `summary_additions`/`summary_deletions`/`summary_files` de la table session

```swift
struct TaskCompletionInfo {
    let sessionID: String
    let sessionTitle: String
    let summary: String          // "Refactored auth middleware"
    let filesChanged: Int?       // 12
    let additions: Int?          // +234
    let deletions: Int?          // -89
}
```

## UI

```
┌──────────────────────────────────────────┐
│  [🎉 celebrate]  ███ NOTCH ███  [3]      │
├──────────────────────────────────────────┤
│  ✅ api-refactor terminée                 │
│  "Refactored auth middleware"             │
│  12 files · +234 -89                      │
│                             [Ouvrir ↗]   │
└──────────────────────────────────────────┘
         ▼ auto-dismiss 5s ▼
┌──────────────────────────────────────────┐
│  [idle]  ███ NOTCH ███  [3]              │
└──────────────────────────────────────────┘
```

### Animation

```swift
// 1. Expand (spring 0.3s)
// 2. Avatar → .celebrate
// 3. Timer 5s
// 4. Collapse (ease-out 0.3s)
// 5. Avatar → .idle

withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
    notchState = .notification(completion)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    withAnimation(.easeOut(duration: 0.3)) {
        notchState = .collapsed
    }
}
```

### Bouton "Ouvrir"

Ouvre le terminal contenant la session. Approches :
1. **AppleScript** : `tell application "Terminal" to activate` (ou iTerm2, Warp, etc.)
2. **NSWorkspace** : activer l'app terminal par bundle ID
3. Best effort — on ne peut pas forcément focus le bon onglet/panneau

## Tâches

- [ ] Implémenter `CompletionDetector` avec heuristique multi-signaux
- [ ] Implémenter `TaskCompletionView` : layout notification
- [ ] Implémenter auto-dismiss avec timer 5s
- [ ] Connecter avatar → `.celebrate` sur complétion
- [ ] Implémenter bouton "Ouvrir" (activate terminal app)
- [ ] Gérer le conflit : permission request + completion simultanés (permission prioritaire)
- [ ] Tester : lancer une tâche OC → vérifier notification à la fin

## Critères d'acceptation

1. Notification apparaît en < 5s après complétion réelle
2. Résumé lisible (titre + stats)
3. Auto-dismiss après 5s sans interaction
4. Clic "Ouvrir" active l'app terminal
5. Si permission request arrive pendant notification → permission prend le dessus
