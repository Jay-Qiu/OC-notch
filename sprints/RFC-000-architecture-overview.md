# RFC-000 — Architecture Overview & Sprint Plan

**Date** : 2026-04-17
**Rôle** : Tech Lead
**Scope** : Plan d'implémentation complet OC-Notch

---

## Architecture globale

```
┌─────────────────────────────────────────────────────────┐
│                      OC-Notch App                       │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  NotchPanel  │  │   Session    │  │    Avatar     │  │
│  │  (NSPanel)   │  │   Monitor    │  │   Engine      │  │
│  │  RFC-001     │  │   Service    │  │  (SpriteKit)  │  │
│  │              │  │   RFC-002    │  │   RFC-003     │  │
│  └──────┬───────┘  └──────┬───────┘  └───────────────┘  │
│         │                 │                              │
│  ┌──────┴─────────────────┴──────────────────────────┐  │
│  │              SwiftUI View Layer                    │  │
│  │                                                    │  │
│  │  ┌─────────────────┐  ┌────────────────────────┐  │  │
│  │  │ Permission UI   │  │  Completion Notif UI   │  │  │
│  │  │ RFC-004         │  │  RFC-005               │  │  │
│  │  └─────────────────┘  └────────────────────────┘  │  │
│  │                                                    │  │
│  │  ┌─────────────────┐                              │  │
│  │  │ Session Counter │                              │  │
│  │  │ & Dropdown      │                              │  │
│  │  │ RFC-006         │                              │  │
│  │  └─────────────────┘                              │  │
│  └────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────┴────┐  ┌─────┴─────┐  ┌─────┴─────┐
         │ SSE     │  │  REST     │  │  SQLite   │
         │ Events  │  │  API      │  │  Direct   │
         │ Stream  │  │ /permission│  │  Reader   │
         └────┬────┘  │ /session  │  └─────┬─────┘
              │       └─────┬─────┘        │
              └─────────────┼──────────────┘
                            │
                   ┌────────┴────────┐
                   │   OpenCode      │
                   │   HTTP Server   │
                   │   (localhost)   │
                   └─────────────────┘
```

## Communication avec OpenCode — Stratégie retenue

### Primaire : HTTP API + SSE
OpenCode expose un serveur HTTP local avec :
- **REST** : CRUD sessions, reply permissions
- **SSE** : stream temps réel de tous les events (permission.asked, session.updated, todo.updated, etc.)
- **OpenAPI spec** à `/doc`

### Secondaire : SQLite direct read
Quand le serveur HTTP n'est pas disponible (mode TUI sans web server), lecture directe de `~/.local/share/opencode/opencode.db`.

### Futur : Plugin OpenCode
Un plugin dédié OC-Notch pourrait :
- Garantir un canal IPC stable
- Exposer des events custom enrichis
- Être distribué via npm

## Sprint Plan

```
Sprint 1 (S1-S2)  ─── Fondations
├── RFC-001: Notch Window Shell      ← fenêtre overlay
└── RFC-002: OpenCode Session Monitor ← détection sessions/events

Sprint 2 (S3-S4)  ─── Core Features  
├── RFC-003: Pixel Avatar Engine     ← sprite animé
└── RFC-004: Permission Request UI   ← extension notch + réponses

Sprint 3 (S5-S6)  ─── Complete MVP
├── RFC-005: Task Completion Notifs  ← notifications fin de tâche
└── RFC-006: Session Counter + Dropdown

Sprint 4 (S7-S8)  ─── Polish (Phase 2 CDC)
├── RFC-007: Keyboard Shortcuts      ← ⌘Y/⌘N pour permissions
├── RFC-008: Sprite Library           ← choix avatar + évolutions
└── RFC-009: Sound & Haptics          ← sons notification
```

## Décisions techniques clés

| Décision | Choix | Raison |
|----------|-------|--------|
| Langage | Swift + SwiftUI | Accès natif NSPanel, performance, animations |
| Window type | NSPanel non-activating | Ne vole pas le focus |
| Sprite engine | SpriteKit (SKScene) | `filteringMode = .nearest` pour pixel-perfect |
| IPC primaire | HTTP API + SSE | Déjà implémenté dans OpenCode, typé, temps réel |
| IPC fallback | SQLite direct read | Fonctionne même sans web server |
| State management | @Observable (Observation framework) | macOS 14+, natif, performant |
| Animations | SwiftUI spring animations | Fluide, déclaratif |
| Min macOS | 14 Sonoma | Pour @Observable. Ventura si on utilise @StateObject fallback |

## Risques techniques identifiés

| # | Risque | Sévérité | Mitigation | RFC |
|---|--------|----------|------------|-----|
| R1 | Port HTTP OpenCode non découvrable | Haute | Investiguer fichier lock / CLI args. Fallback SQLite. | RFC-002 |
| R2 | Serveur HTTP absent en mode TUI | Moyenne | SQLite polling fallback. Proposer un plugin OC. | RFC-002 |
| R3 | canBecomeKey=false bloque les interactions | Moyenne | Boutons marchent sans key. Tester NSPanel mouse events. | RFC-004 |
| R4 | Complétion détection faux positifs | Moyenne | Heuristique multi-signaux + debounce 5s | RFC-005 |
| R5 | Sprites Pokémon — IP concerns | Basse | Créer des sprites originaux pixel-art, pas des copies | RFC-003 |

## Spike requis avant Sprint 1

**Spike-001** : Trouver comment découvrir le port HTTP de chaque instance OpenCode
- Scanner les process args
- Chercher un fichier lock/port file
- Tester avec `opencode web --port`
- Lire le code source de `packages/opencode/src/cli/cmd/web.ts`

**Spike-002** : Confirmer que le mode TUI expose aussi le serveur HTTP ou non
- Lancer `opencode` (TUI) et tester `curl localhost:<port>/session/`
