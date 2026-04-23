# RFC-009 — Multi-Session Question Queue & Routing

**Sprint** : 4 (Semaine 7-8)
**Priorite** : P0
**Dependances** : RFC-002 (SessionMonitor), RFC-004 (Permission Request UI)
**References CDC** : F-PR-08 (queue de demandes), F-SC-02 (indicateur d'etat)

---

## Contexte

Aujourd'hui le `PermissionQueueManager` (RFC-004) gere une file de permissions, mais il n'est pas concu pour gerer des questions provenant de **sessions differentes simultanement**. Le use case reel : l'utilisateur a 2-3 sessions OpenCode ouvertes, chacune peut poser des questions en meme temps.

**Probleme** : Si la session A pose 3 questions et la session B pose 2 questions, il faut :
1. Presenter les questions d'une session a la fois (pas un melange)
2. Apres avoir repondu aux questions de la session A, enchainer automatiquement avec celles de la session B
3. **Chaque reponse doit etre routee vers le bon terminal** (session A ou B)

## Decision technique

### Modele de donnees : Queue hierarchique

```
SessionQuestionQueue (global)
├── SessionA: [Question1, Question2, Question3]  ← groupe courant
├── SessionB: [Question1, Question2]             ← groupe suivant
└── SessionC: [Question1]                        ← groupe en attente

Ordre de traitement : FIFO par session (premiere session a poser une question = premiere servie)
Au sein d'une session : questions dans l'ordre de reception
```

### Architecture

```swift
@Observable
class MultiSessionQueueManager {
    /// File ordonnee par session — FIFO sur l'ordre d'arrivee de la premiere question
    private(set) var sessionQueues: OrderedDictionary<SessionID, [PendingInteraction]> = [:]
    
    /// La session dont les questions sont actuellement affichees
    var activeSessionID: SessionID? {
        sessionQueues.keys.first
    }
    
    /// Les interactions de la session active
    var currentInteractions: [PendingInteraction] {
        guard let id = activeSessionID else { return [] }
        return sessionQueues[id] ?? []
    }
    
    /// Nombre total de sessions en attente
    var waitingSessionCount: Int {
        sessionQueues.count
    }
    
    // MARK: - Ingestion
    
    func enqueue(_ interaction: PendingInteraction, for sessionID: SessionID) {
        if sessionQueues[sessionID] == nil {
            sessionQueues[sessionID] = []
        }
        sessionQueues[sessionID]?.append(interaction)
    }
    
    // MARK: - Reponse
    
    /// Repond a une interaction specifique — route vers le bon terminal
    func reply(to interactionID: InteractionID, response: InteractionResponse) async throws {
        guard let sessionID = findSession(for: interactionID) else { return }
        
        // Route la reponse vers la bonne session via HTTP API
        try await httpClient.replyInteraction(
            sessionID: sessionID,
            interactionID: interactionID,
            response: response
        )
        
        // Retire de la queue
        sessionQueues[sessionID]?.removeAll { $0.id == interactionID }
        
        // Si plus de questions pour cette session → passer a la suivante
        if sessionQueues[sessionID]?.isEmpty == true {
            sessionQueues.removeValue(forKey: sessionID)
            // La session suivante devient automatiquement active
            // via activeSessionID = sessionQueues.keys.first
        }
    }
    
    /// Auto-dismiss : si une question est resolue cote terminal
    func dismiss(interactionID: InteractionID) {
        for (sessionID, _) in sessionQueues {
            sessionQueues[sessionID]?.removeAll { $0.id == interactionID }
            if sessionQueues[sessionID]?.isEmpty == true {
                sessionQueues.removeValue(forKey: sessionID)
            }
        }
    }
}
```

### Routing des reponses — Garantie de correctitude

Chaque `PendingInteraction` porte :
- `sessionID` : identifiant de la session source
- `interactionID` / `requestID` : identifiant unique de la question/permission
- Le endpoint REST inclut le `sessionID` dans le path ou le body

```
POST /session/{sessionID}/permission/{requestID}/reply
POST /session/{sessionID}/question/{questionID}/reply

→ OpenCode route la reponse au bon terminal via le sessionID
```

**Invariant critique** : une reponse ne peut JAMAIS etre envoyee sans `sessionID` explicite. Le `MultiSessionQueueManager` enforce cet invariant au compile time.

### Flow UX

```
Etat initial: notch idle
  │
  ├─ Session A: question recue
  │    → Notch s'etend, affiche question A.1
  │    → Avatar: alert
  │    → Indicateur: "Session A — 1/3 questions • +1 session en attente"
  │
  ├─ User repond a A.1
  │    → Reponse routee vers terminal A
  │    → Affiche question A.2
  │
  ├─ User repond a A.2, puis A.3
  │    → Session A terminee
  │    → TRANSITION AUTOMATIQUE vers Session B
  │    → Animation: slide horizontal (A sort a gauche, B entre a droite)
  │    → Indicateur: "Session B — 1/2 questions"
  │
  ├─ User repond a B.1, puis B.2
  │    → Toutes les sessions traitees
  │    → Notch se referme
  │    → Avatar: idle
  │
  └─ Si nouvelle question arrive pendant le traitement de A :
       → Si meme session A : ajoutee a la fin de sa queue
       → Si nouvelle session C : ajoutee en fin de file globale
```

### Indicateur visuel de la file

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 sessions]   │
├──────────────────────────────────────────┤
│  ❓ api-refactor (session A)             │  ← session active
│                                          │
│  "Which testing framework to use?"       │
│  ┌─────────┐ ┌────────┐ ┌──────────┐   │
│  │ vitest  │ │ jest   │ │ mocha    │   │
│  └─────────┘ └────────┘ └──────────┘   │
│                                          │
│  Question 1/3  •  +1 session en attente  │  ← compteurs
│  ● ● ○   [auth-migration ⏳]            │  ← dots + preview session suivante
└──────────────────────────────────────────┘
```

### Transition entre sessions

Animation de transition quand on passe d'une session a l'autre :

```swift
.transition(
    .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
)
.animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSessionID)
```

### Synchronisation avec le dropdown (RFC-006)

Les sessions en attente de reponse sont marquees `.waiting` (rouge) dans le dropdown.
Quand une session est la session active (questions affichees), elle a un indicateur special (ex: surbrillance, fleche).

## Taches

- [ ] Creer `MultiSessionQueueManager` remplacant/etendant `PermissionQueueManager`
- [ ] Implementer la queue hierarchique (FIFO par session)
- [ ] Implementer le routing des reponses avec `sessionID` explicite
- [ ] Implementer la transition automatique entre sessions quand une file est videe
- [ ] Implementer l'animation de transition (slide horizontal)
- [ ] Ajouter l'indicateur "Question X/N • +M sessions en attente" dans la vue
- [ ] Ajouter la preview de la session suivante en bas
- [ ] Connecter au `SessionMonitorService` pour la reception des events SSE multi-session
- [ ] Implementer l'auto-dismiss quand une question est resolue cote terminal
- [ ] Synchroniser l'etat `.waiting` avec le dropdown (RFC-006)
- [ ] Tester : 2 sessions posent des questions simultanement → reponses routees correctement
- [ ] Tester : repondre dans le terminal directement → question retiree de la file sans casser la suite
- [ ] Tester : nouvelle question arrive pendant le traitement → ajoutee au bon endroit

## Criteres d'acceptation

1. Questions groupees par session — jamais de melange entre sessions
2. Transition automatique vers la session suivante en < 500ms apres la derniere reponse
3. Chaque reponse est routee vers le bon terminal (verifiable : l'agent de la bonne session continue)
4. L'indicateur affiche correctement le nombre de questions et de sessions en attente
5. Une question resolue cote terminal est retiree de la file sans perturber le flow courant
6. Le dropdown (RFC-006) reflete l'etat `.waiting` en temps reel pour chaque session en attente
7. Le flow fonctionne avec 3+ sessions posant des questions simultanement
