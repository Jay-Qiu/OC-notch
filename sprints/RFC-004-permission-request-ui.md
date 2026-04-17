# RFC-004 — Permission Request UI (Notch Extension)

**Sprint** : 2 (Semaine 3-4)
**Priorité** : P0
**Dépendances** : RFC-001 (NotchPanel), RFC-002 (SessionMonitor)
**Références CDC** : F-PR-01 → F-PR-08

---

## Contexte

Feature critique : quand un agent demande une permission, le notch s'étend vers le bas pour afficher la demande et des boutons de réponse. L'utilisateur répond directement, la réponse est transmise à OpenCode via REST API.

## Décision technique

### Animation d'extension

```swift
struct NotchShellView: View {
    @State var expandedHeight: CGFloat = 0  // 0 = collapsed
    
    var body: some View {
        VStack(spacing: 0) {
            // Barre permanente (avatar + compteur)
            NotchBarView()
                .frame(height: 36)
            
            // Zone extensible
            if expandedHeight > 0 {
                PermissionRequestView(request: currentRequest)
                    .frame(height: expandedHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expandedHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}
```

### Layout permission request

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 sessions]   │  ← barre permanente
├──────────────────────────────────────────┤
│  ⚠ api-refactor                          │  ← nom session
│                                          │
│  Exécuter:                               │  ← label action
│  ┌──────────────────────────────────┐    │
│  │ rm -rf ./dist && npm run build  │    │  ← commande (monospace, scrollable)
│  └──────────────────────────────────┘    │
│                                          │
│  [✓ Autoriser]  [✕ Refuser]             │  ← boutons
│                                          │
│  ● ● ○  (2 demandes en attente)         │  ← pagination si queue
└──────────────────────────────────────────┘
```

### Flow de données

```
1. SSE event "permission.asked" reçu
   → { requestID, sessionID, permission: "bash", metadata: { command: "..." } }

2. SessionMonitorService.pendingPermissions.append(request)

3. NotchShellView observe pendingPermissions
   → expandedHeight = 140
   → Avatar passe en .alert

4. User clique "Autoriser"
   → POST /permission/{requestID}/reply { "allow": true }
   → Retirer de pendingPermissions
   → Si queue vide: expandedHeight = 0, avatar → .idle
   → Si queue non vide: afficher demande suivante
```

### Interaction sans focus steal

```swift
// Le panel ne devient jamais key window
// Les boutons utilisent NSPanel behavior spécial

class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    // Exception: quand permission UI est visible, accepter les clics
    // mais NE PAS prendre le keyboard focus
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // Handle button click sans devenir key
            super.sendEvent(event)
        }
    }
}
```

**Important** : `canBecomeKey = false` empêche les TextField mais les boutons fonctionnent. C'est OK car on n'a que des boutons dans la permission UI.

### Queue de permissions

```swift
@Observable
class PermissionQueueManager {
    var queue: [OCPermissionRequest] = []
    var currentIndex: Int = 0
    
    var current: OCPermissionRequest? { 
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil 
    }
    
    func reply(allow: Bool) async {
        guard let request = current else { return }
        try await httpClient.replyPermission(requestID: request.id, allow: allow)
        queue.remove(at: currentIndex)
        if currentIndex >= queue.count { currentIndex = max(0, queue.count - 1) }
    }
}
```

## Tâches

- [ ] Implémenter `PermissionRequestView` : layout de la demande
- [ ] Implémenter animation spring d'expansion/collapse du notch
- [ ] Connecter au `SessionMonitorService` pour les events `permission.asked`
- [ ] Implémenter `PermissionQueueManager` pour gérer les demandes multiples
- [ ] Implémenter le call REST `POST /permission/:requestID/reply`
- [ ] Implémenter auto-dismiss quand la permission est résolue côté terminal
- [ ] Implémenter navigation entre demandes (points de pagination)
- [ ] Tester : répondre depuis le notch → vérifier que l'agent continue dans le terminal

## Critères d'acceptation

1. Extension du notch en < 300ms (spring animation)
2. Commande exacte affichée lisiblement (monospace, overflow scroll)
3. Clic "Autoriser" → agent continue dans le terminal en < 1s
4. Clic "Refuser" → agent reçoit le deny
5. Si répondu dans le terminal directement → notch se referme automatiquement
6. Queue fonctionne : 3 permissions simultanées navigables
