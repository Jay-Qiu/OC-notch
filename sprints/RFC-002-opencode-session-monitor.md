# RFC-002 — OpenCode Session Monitor

**Sprint** : 1 (Semaine 1-2)
**Priorité** : P0 — Fondation
**Dépendances** : Aucune (backend, pas de UI)
**Références CDC** : F-SC-01, F-PR-01, F-NT-01

---

## Contexte

OC-Notch doit détecter les sessions OpenCode actives, les permission requests, et les complétions de tâche. OpenCode expose une architecture riche qu'on peut exploiter.

## Découvertes techniques — Architecture OpenCode

### Base de données
- **Chemin** : `~/.local/share/opencode/opencode.db` (SQLite)
- **Tables clés** : `session`, `message`, `part`, `todo`, `permission`, `event`
- **Session** : `id`, `project_id`, `title`, `permission` (JSON array de rules), `time_created/updated`
- **Todo** : `session_id`, `content`, `status` (pending/in_progress/completed), `priority`
- **Part** : `data` contient les tool calls avec `state.status` (running/completed/error)

### HTTP API + SSE (méthode principale)
OpenCode lance un serveur HTTP local (`opencode web` ou intégré au TUI). 

**Endpoints clés** :
```
GET  /session/                    → liste des sessions
GET  /session/:id                 → détails session
GET  /session/:id/message/        → messages de la session
GET  /permission/                 → permissions en attente
POST /permission/:requestID/reply → répondre (allow/deny)
GET  /event                       → SSE stream de tous les events
GET  /doc                         → OpenAPI spec
```

**Events SSE clés** :
```
permission.asked    → { requestID, sessionID, permission, tool, ... }
session.updated     → { session object }
message.updated     → { message object }
message.part.updated → { part avec tool state }
todo.updated        → { session_id, todos[] }
```

### SDK TypeScript
```typescript
import { createOpencodeClient } from "@opencode-ai/sdk"
// Fournit un client typé pour tous les endpoints
```

### Plugin System
OpenCode supporte des plugins avec hooks :
- `permission.ask` — intercepter les demandes de permission
- `event` — écouter tous les events du bus

## Décision technique

### Approche hybride : SSE (primaire) + SQLite (fallback)

```
┌─────────────────────────────────┐
│     SessionMonitorService       │
│                                 │
│  ┌───────────┐  ┌───────────┐  │
│  │  SSE      │  │  SQLite   │  │
│  │  Client   │  │  Poller   │  │
│  │ (primary) │  │ (fallback)│  │
│  └─────┬─────┘  └─────┬─────┘  │
│        │               │        │
│        └───────┬───────┘        │
│                │                │
│         ┌──────┴──────┐        │
│         │  Unified    │        │
│         │  Event Bus  │        │
│         └──────┬──────┘        │
│                │                │
└────────────────┼────────────────┘
                 │
          SwiftUI @Observable
```

### Détection des instances OpenCode actives

```swift
// 1. Scanner les processus actifs
func findOpenCodeProcesses() -> [OCProcess] {
    // Chercher les processus "opencode" via ProcessInfo/libproc
    // Extraire le port HTTP de chaque instance (args ou fichier lock)
}

// 2. Fallback: lire la DB SQLite directement
func readSessionsFromDB() -> [OCSession] {
    let db = try SQLite("~/.local/share/opencode/opencode.db")
    return db.query("SELECT * FROM session WHERE time_archived IS NULL ORDER BY time_updated DESC")
}
```

### Connexion SSE par instance

```swift
class OpenCodeSSEClient {
    let baseURL: URL  // http://localhost:<port>
    
    func connect() -> AsyncStream<OCEvent> {
        // EventSource sur GET /event
        // Parse les events SSE typés
    }
    
    func replyPermission(requestID: String, allow: Bool) async throws {
        // POST /permission/:requestID/reply
    }
    
    func listPendingPermissions() async throws -> [Permission] {
        // GET /permission/
    }
}
```

### Détection de complétion

Plusieurs signaux combinés :
1. **Todo status** : quand tous les todos passent à `completed` → tâche terminée
2. **Message idle** : pas de nouveau `message.part.updated` depuis > 5s après un message assistant
3. **Session updated** : `summary_additions`/`summary_deletions` changent → diff terminé

## Tâches

- [ ] Implémenter `ProcessScanner` : détection des processus opencode actifs + ports HTTP
- [ ] Implémenter `OpenCodeSSEClient` : connexion SSE, parsing events typés
- [ ] Implémenter `OpenCodeHTTPClient` : REST calls (sessions, permissions, reply)
- [ ] Implémenter `SQLiteReader` : lecture directe de la DB (fallback)
- [ ] Implémenter `SessionMonitorService` : agrégation, @Observable state
- [ ] Définir les modèles Swift : `OCSession`, `OCPermissionRequest`, `OCTaskCompletion`
- [ ] Implémenter détection de complétion (heuristique multi-signaux)
- [ ] Tests unitaires avec mock SSE server

## Critères d'acceptation

1. Détecte toutes les sessions OpenCode actives en < 2s
2. Reçoit les `permission.asked` events en temps réel via SSE
3. Peut répondre allow/deny via REST API et la réponse est effective
4. Détecte la complétion de tâche en < 5s
5. Fallback SQLite fonctionne si le serveur HTTP n'est pas disponible

## Questions ouvertes

- **Comment trouver le port HTTP de chaque instance OpenCode ?** Investiguer : fichier lock, args process, port fixe configurable
- **Le serveur HTTP est-il toujours actif en mode TUI ?** À confirmer — sinon le mode SSE ne marche qu'avec `opencode web`
- **Faut-il écrire un plugin OpenCode ?** Un plugin pourrait exposer les events de manière plus fiable qu'un client externe
