# RFC-011 — Dismiss Question sans Repondre

**Sprint** : 4 (Semaine 7-8)
**Priorite** : P1
**Dependances** : RFC-009 (Multi-Session Queue), RFC-006 (Session Dropdown)
**References CDC** : F-SC-02 (indicateur d'etat par session)

---

## Contexte

Quand une question ou permission request est affichee dans le notch, l'utilisateur n'a aujourd'hui que deux options : repondre ou attendre. Parfois, l'utilisateur veut **ignorer temporairement** la question — soit parce qu'il n'a pas le contexte, soit parce qu'il veut y repondre plus tard directement dans le terminal.

**Objectif** : Permettre a l'utilisateur de "dismiss" une question affichee dans le notch. Cela :
1. Ferme le formulaire dans le notch
2. Affiche les sessions actives (retour au mode normal)
3. **N'envoie aucune reponse au terminal** — la session reste en attente

## Decision technique

### Bouton Dismiss

Un bouton "X" (fermer) ou "Ignorer" est ajoute a chaque vue de question/permission.

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 sessions]   │
├──────────────────────────────────────────┤
│  ❓ api-refactor                    [✕]  │  ← bouton dismiss
│                                          │
│  "Which testing framework to use?"       │
│  ┌─────────┐ ┌────────┐ ┌──────────┐   │
│  │ vitest  │ │ jest   │ │ mocha    │   │
│  └─────────┘ └────────┘ └──────────┘   │
│                                          │
│  Question 1/3  •  [Ignorer cette session]│  ← lien alternatif
└──────────────────────────────────────────┘
```

Deux niveaux de dismiss :
- **`[✕]` (dismiss question)** : ignore la question courante, passe a la suivante dans la meme session
- **`[Ignorer cette session]`** : ignore toutes les questions de la session active, passe a la session suivante

### Comportement detaille

#### Dismiss une question

```
User clique [✕] sur question A.2
  │
  ├─ La question A.2 est retiree de la vue (animation fade out)
  ├─ La question A.2 est deplacee dans dismissedInteractions (pas supprimee)
  ├─ AUCUNE reponse HTTP n'est envoyee au terminal
  ├─ Le terminal de la session A reste en attente (bloque)
  │
  ├─ S'il reste des questions pour la session A :
  │    → Affiche question A.3
  │
  └─ Si plus de questions pour session A ET d'autres sessions en attente :
       → Transition vers session B (comme RFC-009)
       → Si plus aucune session : notch se referme, retour au mode idle
```

#### Dismiss une session entiere

```
User clique [Ignorer cette session]
  │
  ├─ Toutes les questions de la session A sont retirees de la vue
  ├─ Toutes deplacees dans dismissedInteractions
  ├─ AUCUNE reponse envoyee
  ├─ Transition vers session B (ou mode idle si plus rien)
  │
  └─ La session A reste en .waiting (rouge) dans le dropdown (RFC-006)
```

### Etat `.waiting` dans le dropdown

Apres dismiss, la session apparait dans le dropdown avec un indicateur specifique :

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 ▼]          │
├──────────────────────────────────────────┤
│  ◍ api-refactor     OC-notch   ⏳ 2 Q   │  ← rouge, "2 Q" = 2 questions en attente
│  ● auth-migration   nova       2m        │  ← vert = idle
│  ◉ db-schema        poker      ▶ 12s     │  ← jaune = active
└──────────────────────────────────────────┘
```

- Pastille rouge (`.waiting`)
- Indication du nombre de questions ignorees/en attente ("2 Q")
- Clic sur la session → re-affiche ses questions dans le notch (reprise du flow)

### Re-affichage des questions ignorees

Si l'utilisateur clique sur une session `.waiting` dans le dropdown :
1. Les questions dismissees de cette session sont re-affichees dans le notch
2. Le flow reprend la ou il s'etait arrete
3. Si entre-temps le terminal a recu une reponse (via le terminal directement), les questions resolues sont retirees

### Implementation

```swift
@Observable
class MultiSessionQueueManager {
    // ... (existant RFC-009) ...
    
    /// Questions dismissees mais toujours en attente cote terminal
    private(set) var dismissedInteractions: OrderedDictionary<SessionID, [PendingInteraction]> = [:]
    
    /// Dismiss une question sans repondre
    func dismiss(interactionID: InteractionID) {
        guard let sessionID = findSession(for: interactionID) else { return }
        guard let index = sessionQueues[sessionID]?.firstIndex(where: { $0.id == interactionID }) else { return }
        
        let interaction = sessionQueues[sessionID]!.remove(at: index)
        
        // Deplacer dans dismissed (pas supprimer)
        if dismissedInteractions[sessionID] == nil {
            dismissedInteractions[sessionID] = []
        }
        dismissedInteractions[sessionID]?.append(interaction)
        
        // Cleanup si plus de questions actives pour cette session
        if sessionQueues[sessionID]?.isEmpty == true {
            sessionQueues.removeValue(forKey: sessionID)
        }
        
        // NE PAS appeler httpClient — aucune reponse envoyee
    }
    
    /// Dismiss toutes les questions d'une session
    func dismissSession(_ sessionID: SessionID) {
        guard let interactions = sessionQueues.removeValue(forKey: sessionID) else { return }
        if dismissedInteractions[sessionID] == nil {
            dismissedInteractions[sessionID] = []
        }
        dismissedInteractions[sessionID]?.append(contentsOf: interactions)
    }
    
    /// Re-afficher les questions ignorees d'une session
    func resumeSession(_ sessionID: SessionID) {
        guard let interactions = dismissedInteractions.removeValue(forKey: sessionID) else { return }
        // Remettre en tete de la queue
        sessionQueues.updateValue(interactions, forKey: sessionID, insertingAt: 0)
    }
    
    /// Sessions qui ont des questions dismissees (pour le dropdown)
    var sessionsWithDismissedQuestions: Set<SessionID> {
        Set(dismissedInteractions.keys)
    }
    
    func dismissedCount(for sessionID: SessionID) -> Int {
        dismissedInteractions[sessionID]?.count ?? 0
    }
}
```

### Auto-cleanup des dismissed

Si le terminal resout une question de lui-meme (l'utilisateur repond dans le terminal), le SSE event `permission.resolved` / `question.answered` doit retirer la question des `dismissedInteractions` :

```swift
func handleResolvedEvent(interactionID: InteractionID) {
    // Retirer de la queue active (RFC-009)
    removeFromActiveQueue(interactionID)
    // Retirer aussi des dismissed
    for (sessionID, _) in dismissedInteractions {
        dismissedInteractions[sessionID]?.removeAll { $0.id == interactionID }
        if dismissedInteractions[sessionID]?.isEmpty == true {
            dismissedInteractions.removeValue(forKey: sessionID)
        }
    }
}
```

## Taches

- [ ] Ajouter le bouton `[✕]` (dismiss) sur chaque vue de question/permission
- [ ] Ajouter le lien "[Ignorer cette session]" en bas de la vue
- [ ] Implementer `dismiss(interactionID:)` dans `MultiSessionQueueManager`
- [ ] Implementer `dismissSession(_:)` pour ignorer toute une session
- [ ] Implementer `resumeSession(_:)` pour re-afficher les questions ignorees
- [ ] Ajouter le tracking des `dismissedInteractions` (questions ignorees mais en attente)
- [ ] Mettre a jour le dropdown (RFC-006) : afficher le compteur de questions en attente pour les sessions `.waiting`
- [ ] Implementer le clic sur une session `.waiting` dans le dropdown → re-affiche les questions
- [ ] Implementer l'auto-cleanup : quand une question dismissed est resolue cote terminal, la retirer
- [ ] Animation de dismiss (fade out + slide de la question suivante)
- [ ] Tester : dismiss une question → terminal reste bloque, aucune reponse envoyee
- [ ] Tester : dismiss toute une session → transition vers la session suivante
- [ ] Tester : reprendre une session dismissee via le dropdown
- [ ] Tester : repondre dans le terminal → question retiree des dismissed automatiquement

## Criteres d'acceptation

1. Clic `[✕]` → la question disparait du notch, AUCUNE reponse n'est envoyee au terminal
2. Le terminal de la session reste bloque en attente (verifiable dans le terminal)
3. La session dismissee apparait en rouge `.waiting` dans le dropdown avec le compteur "N Q"
4. Clic sur la session dans le dropdown → les questions ignorees re-apparaissent
5. Si la question est resolue cote terminal entre-temps → elle est retiree automatiquement des dismissed
6. "Ignorer cette session" → toutes les questions de la session sont dismissees d'un coup
7. Le flow multi-session (RFC-009) fonctionne normalement apres un dismiss (transition vers session suivante)
