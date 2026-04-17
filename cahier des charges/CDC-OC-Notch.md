# Cahier des Charges — OC-Notch

## Application macOS d'interaction avec les sessions AI agents via le notch du MacBook

**Version** : 1.0
**Date** : 2026-04-17
**Auteur** : Product Owner

---

## 1. Vision produit

OC-Notch est une application macOS native qui exploite l'espace autour du notch du MacBook pour offrir une interface compacte et réactive de monitoring et d'interaction avec les sessions d'agents IA (OpenCode, Claude Code). L'application transforme le notch — habituellement un espace mort — en un hub de supervision des agents.

---

## 2. Utilisateurs cibles

| Persona | Description |
|---------|-------------|
| **Développeur multi-sessions** | Utilise 2-10+ sessions OpenCode/Claude Code en parallèle dans différents terminaux. A besoin de visibilité centralisée et de répondre rapidement aux prompts d'autorisation sans chercher le bon terminal. |

---

## 3. Objectifs business

| # | Objectif | KPI |
|---|----------|-----|
| O1 | Réduire le temps de réaction aux permission requests des agents | Temps moyen < 3s (vs chercher le terminal ~15-30s) |
| O2 | Ne jamais rater une fin de tâche agent | 100% des notifications de complétion affichées |
| O3 | Offrir une expérience "delightful" autour du notch | Rétention utilisateur > 80% à 30 jours |

---

## 4. Périmètre fonctionnel

### 4.1 — Zone Notch : Layout permanent

```
┌─────────────────────────────────────────────────┐
│  [Pokemon pixelisé]  ███ NOTCH ███  [3 sessions] │
│   animation idle      (hardware)     compteur    │
└─────────────────────────────────────────────────┘
```

#### 4.1.1 — Avatar Pokémon (gauche du notch)

| ID | Fonctionnalité | Priorité | Détails |
|----|---------------|----------|---------|
| F-AV-01 | Affichage avatar pixelisé | P0 | Sprite Pokémon pixel-art 32x32 ou 48x48, rendu net (pas de lissage) |
| F-AV-02 | Animation idle | P0 | Boucle d'animation au repos (2-4 frames, respiration/rebond) |
| F-AV-03 | Animation contextuelle | P1 | États : idle, thinking (agent travaille), alert (permission request), celebration (tâche terminée) |
| F-AV-04 | Choix du Pokémon | P2 | Sélection parmi une bibliothèque de sprites pixel-art |
| F-AV-05 | Pokémon lié à l'état global | P2 | Évolution visuelle selon nombre de tâches complétées (ex: Salamèche → Dracaufeu) |

#### 4.1.2 — Compteur de sessions (droite du notch)

| ID | Fonctionnalité | Priorité | Détails |
|----|---------------|----------|---------|
| F-SC-01 | Compteur sessions actives | P0 | Nombre de sessions OpenCode actuellement ouvertes |
| F-SC-02 | Indicateur d'état par session | P1 | Pastilles de couleur : vert (idle), jaune (en cours), rouge (attend input) |
| F-SC-03 | Click → liste des sessions | P1 | Dropdown listant les sessions avec nom/projet, état, durée |

### 4.2 — Notch étendu : Permission Requests

Quand un agent demande une autorisation utilisateur, le notch s'agrandit vers le bas.

```
┌─────────────────────────────────────────────────┐
│  [Pokemon alert]     ███ NOTCH ███  [3 sessions] │
├─────────────────────────────────────────────────┤
│  ⚠ Session "api-refactor" demande :              │
│  "Exécuter: rm -rf ./dist && npm run build"      │
│                                                   │
│  [ Autoriser ]  [ Refuser ]  [ Voir contexte ]   │
└─────────────────────────────────────────────────┘
```

| ID | Fonctionnalité | Priorité | Détails |
|----|---------------|----------|---------|
| F-PR-01 | Détection permission request | P0 | Monitoring en temps réel des sessions pour détecter les demandes d'autorisation |
| F-PR-02 | Extension du notch | P0 | Animation d'expansion fluide vers le bas (spring animation, ~300ms) |
| F-PR-03 | Affichage de la commande/action | P0 | Texte exact de ce que l'agent veut exécuter |
| F-PR-04 | Boutons de réponse | P0 | Autoriser / Refuser — réponse transmise au terminal source |
| F-PR-05 | Choix multiples | P1 | Quand l'agent propose plusieurs options, afficher les choix |
| F-PR-06 | "Voir contexte" | P1 | Expand supplémentaire montrant le contexte de la demande |
| F-PR-07 | Auto-dismiss | P1 | Si répondu dans le terminal directement, le notch se referme |
| F-PR-08 | Queue de demandes | P1 | Si plusieurs permissions simultanées, navigation entre elles |
| F-PR-09 | Raccourci clavier | P2 | Répondre sans souris (ex: ⌘Y autoriser, ⌘N refuser) |

### 4.3 — Notch étendu : Notifications de complétion

Quand un agent termine une tâche, le notch s'agrandit brièvement.

```
┌─────────────────────────────────────────────────┐
│  [Pokemon célèbre]   ███ NOTCH ███  [3 sessions] │
├─────────────────────────────────────────────────┤
│  ✅ Session "api-refactor" terminée               │
│  "Refactored auth middleware — 12 files changed"  │
│                                        [Ouvrir]  │
└─────────────────────────────────────────────────┘
```

| ID | Fonctionnalité | Priorité | Détails |
|----|---------------|----------|---------|
| F-NT-01 | Détection fin de tâche | P0 | Monitoring des sessions pour détecter la complétion |
| F-NT-02 | Notification notch | P0 | Extension temporaire du notch (auto-dismiss après 5s) |
| F-NT-03 | Résumé de la tâche | P0 | Nom de session + description courte du travail accompli |
| F-NT-04 | Bouton "Ouvrir" | P1 | Ouvre/focus le terminal de la session concernée |
| F-NT-05 | Son de notification | P2 | Son discret optionnel |
| F-NT-06 | Historique | P2 | Liste des tâches complétées dans la session courante |

---

## 5. Intégration avec OpenCode

### 5.1 — Mécanisme de détection des sessions

| Méthode | Description | Fiabilité |
|---------|-------------|-----------|
| **Processus système** | Scanner les processus `opencode` actifs | Haute — source de vérité pour le compteur |
| **Fichiers session** | Lire les fichiers de session dans `~/.opencode/` | Haute — données structurées |
| **stdout/pty monitoring** | Intercepter les outputs des terminaux pour détecter les prompts | Moyenne — parsing nécessaire |
| **API/IPC OpenCode** | Si OpenCode expose une API locale (socket/HTTP) | Idéale — à investiguer |

### 5.2 — Détection des permission requests

Les agents affichent des patterns reconnaissables quand ils demandent une autorisation :
- OpenCode : patterns de prompt interactif dans le terminal
- Investigation nécessaire : mécanisme exact d'IPC pour intercepter et répondre aux prompts

### 5.3 — Réponse aux prompts

| Approche | Avantages | Inconvénients |
|----------|-----------|---------------|
| **Écriture stdin du processus** | Direct, fiable | Nécessite accès au PTY |
| **Simulation clavier** | Universel | Fragile, nécessite focus |
| **API/socket OpenCode** | Propre, découplé | Dépend de l'implémentation OC |

> **Action requise** : Investiguer l'architecture IPC d'OpenCode pour déterminer la meilleure approche d'intégration.

---

## 6. Architecture technique

### 6.1 — Stack recommandé

| Composant | Technologie | Justification |
|-----------|-------------|---------------|
| **App native** | Swift + SwiftUI | Accès natif au window management macOS, performance, notch positioning |
| **Window management** | NSPanel (non-activating) | Overlay au-dessus du notch sans voler le focus |
| **Sprite rendering** | SpriteKit ou Metal | Animations pixel-art fluides |
| **IPC** | XPC / Unix sockets | Communication avec les processus OpenCode |
| **Monitoring** | `Process` + `FileManager` | Détection des sessions actives |

### 6.2 — Contraintes techniques

| Contrainte | Détail |
|------------|--------|
| CT-01 | L'app ne doit JAMAIS voler le focus clavier à l'utilisateur |
| CT-02 | L'overlay doit rester au-dessus de toutes les fenêtres dans la zone notch |
| CT-03 | Consommation CPU idle < 1%, mémoire < 50MB |
| CT-04 | Compatible MacBook Pro 14" et 16" (tailles de notch différentes) |
| CT-05 | Compatible macOS 13 Ventura+ |
| CT-06 | Pas de dépendance à Accessibility permissions pour les fonctions P0 |

### 6.3 — Diagramme de composants

```
┌──────────────────────────────────────────┐
│              OC-Notch App                │
│                                          │
│  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │ Notch UI │  │ Session  │  │ Sprite │ │
│  │ Manager  │  │ Monitor  │  │ Engine │ │
│  └────┬─────┘  └────┬─────┘  └────────┘ │
│       │              │                    │
│       │         ┌────┴─────┐             │
│       │         │   IPC    │             │
│       │         │  Bridge  │             │
│       │         └────┬─────┘             │
└───────┼──────────────┼───────────────────┘
        │              │
   ┌────┴────┐    ┌────┴─────────────┐
   │  macOS  │    │ OpenCode Process │
   │  Notch  │    │  (Terminal PTY)  │
   │  Area   │    └──────────────────┘
   └─────────┘
```

---

## 7. User Stories

### Epic 1 : Présence notch

| US | En tant que... | Je veux... | Afin de... | Priorité |
|----|---------------|------------|------------|----------|
| US-01 | Dev | Voir un avatar Pokémon pixelisé à gauche du notch | Avoir un compagnon visuel qui rend le monitoring fun | P0 |
| US-02 | Dev | Voir le nombre de sessions OC actives à droite du notch | Savoir d'un coup d'œil combien d'agents tournent | P0 |
| US-03 | Dev | Que l'avatar s'anime différemment selon l'état des agents | Percevoir l'activité sans regarder les terminaux | P1 |

### Epic 2 : Permission requests

| US | En tant que... | Je veux... | Afin de... | Priorité |
|----|---------------|------------|------------|----------|
| US-04 | Dev | Être alerté via le notch quand un agent demande une permission | Ne jamais bloquer un agent en attente | P0 |
| US-05 | Dev | Pouvoir répondre directement depuis le notch | Ne pas avoir à chercher le bon terminal | P0 |
| US-06 | Dev | Voir exactement ce que l'agent veut exécuter | Prendre une décision éclairée | P0 |
| US-07 | Dev | Utiliser un raccourci clavier pour répondre | Gagner encore plus de temps | P2 |

### Epic 3 : Notifications de complétion

| US | En tant que... | Je veux... | Afin de... | Priorité |
|----|---------------|------------|------------|----------|
| US-08 | Dev | Être notifié quand un agent termine sa tâche | Enchaîner rapidement avec la review ou la prochaine tâche | P0 |
| US-09 | Dev | Voir un résumé de ce qui a été fait | Comprendre le résultat sans ouvrir le terminal | P0 |
| US-10 | Dev | Pouvoir ouvrir le terminal de la session d'un clic | Aller directement au résultat | P1 |

---

## 8. Phases de livraison

### Phase 1 — MVP (4-6 semaines)

- [ ] App overlay positionnée autour du notch (F-AV-01, F-AV-02)
- [ ] Détection et comptage des sessions OpenCode actives (F-SC-01)
- [ ] Détection des permission requests (F-PR-01)
- [ ] Extension du notch + boutons Autoriser/Refuser (F-PR-02, F-PR-03, F-PR-04)
- [ ] Notification de complétion de tâche (F-NT-01, F-NT-02, F-NT-03)

### Phase 2 — Polish (3-4 semaines)

- [ ] Animations contextuelles du Pokémon (F-AV-03)
- [ ] Indicateur d'état par session + dropdown (F-SC-02, F-SC-03)
- [ ] Choix multiples pour les permissions (F-PR-05)
- [ ] Auto-dismiss et queue de demandes (F-PR-07, F-PR-08)
- [ ] Bouton "Ouvrir" terminal (F-NT-04)

### Phase 3 — Delight (2-3 semaines)

- [ ] Bibliothèque de Pokémon (F-AV-04)
- [ ] Évolution selon progression (F-AV-05)
- [ ] Raccourcis clavier (F-PR-09)
- [ ] Sons de notification (F-NT-05)
- [ ] Historique des tâches (F-NT-06)

---

## 9. Risques et mitigations

| Risque | Impact | Probabilité | Mitigation |
|--------|--------|-------------|------------|
| Pas d'API IPC stable dans OpenCode pour intercepter les prompts | Bloquant | Moyenne | Investiguer en amont. Fallback : monitoring PTY stdout |
| Apple change le comportement de la zone notch dans une future version macOS | Moyen | Faible | Architecture découplée UI/logique. Adapter le positionnement |
| Performance du monitoring continu | Moyen | Faible | Polling adaptatif (interval plus long si idle). FileSystem events > polling |
| Propriété intellectuelle sprites Pokémon | Moyen | Haute | Utiliser des sprites custom pixel-art inspirés mais originaux, ou un pack libre de droits |

---

## 10. Critères d'acceptation MVP

1. L'app se lance au login et se positionne autour du notch sans voler le focus
2. Un sprite pixelisé animé est visible à gauche du notch
3. Le nombre de sessions OpenCode actives est affiché à droite et mis à jour en < 2s
4. Quand un agent demande une permission, le notch s'étend en < 500ms
5. L'utilisateur peut autoriser/refuser depuis le notch et la réponse est transmise à l'agent
6. Quand un agent termine, une notification apparaît dans le notch pendant 5s
7. CPU idle < 1%, mémoire < 50MB

---

## 11. Hors périmètre (v1)

- Support Claude Code (v2 — architecture similaire, IPC différent)
- Support macOS sans notch (MacBook Air M1, écrans externes)
- App iOS/iPadOS companion
- Dashboard web
- Multi-utilisateur / remote sessions
