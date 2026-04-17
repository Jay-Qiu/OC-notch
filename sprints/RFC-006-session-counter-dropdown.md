# RFC-006 — Session Counter & Dropdown

**Sprint** : 3 (Semaine 5-6)
**Priorité** : P0 (compteur) / P1 (dropdown)
**Dépendances** : RFC-001, RFC-002
**Références CDC** : F-SC-01, F-SC-02, F-SC-03

---

## Contexte

Côté droit du notch : nombre de sessions actives. Clic → dropdown avec liste détaillée.

## Compteur

```swift
struct SessionCounterView: View {
    @Environment(SessionMonitorService.self) var monitor
    
    var body: some View {
        Text("\(monitor.activeSessions.count)")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .contentTransition(.numericText())  // animation chiffre
    }
}
```

## Dropdown

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 ▼]          │  ← clic sur le compteur
├──────────────────────────────────────────┤
│  ● api-refactor        OC-notch   2m     │  ← vert = idle
│  ◉ auth-migration      nova       ▶ 12s  │  ← jaune = active
│  ◍ db-schema           poker      ⏳      │  ← rouge = attend input
└──────────────────────────────────────────┘
```

### Indicateurs d'état

```swift
enum SessionStatus {
    case idle       // vert — pas d'activité
    case active     // jaune — tool en cours d'exécution
    case waiting    // rouge — permission request pending
    
    var color: Color {
        switch self {
        case .idle: .green
        case .active: .yellow
        case .waiting: .red
        }
    }
}
```

Détermination du status :
- **waiting** : `pendingPermissions.contains(where: { $0.sessionID == session.id })`
- **active** : dernier `message.part.updated` < 30s ET part.state.status == "running"
- **idle** : sinon

### Clic sur une session dans le dropdown

→ Ouvre/focus le terminal de cette session (même logique que RFC-005 "Ouvrir")

## Tâches

- [ ] Implémenter `SessionCounterView` avec animation numérique
- [ ] Implémenter `SessionDropdownView` : liste avec état par session
- [ ] Implémenter la logique de détermination du status (idle/active/waiting)
- [ ] Implémenter le toggle dropdown (clic compteur → expand, clic outside → collapse)
- [ ] Implémenter clic session → focus terminal
- [ ] Gérer le conflit dropdown + permission request (permission ferme le dropdown)

## Critères d'acceptation

1. Compteur mis à jour en < 2s quand une session commence/termine
2. Animation numérique fluide sur changement
3. Dropdown liste toutes les sessions avec bon statut
4. Pastilles de couleur correctes (vérifié avec session en attente de permission)
