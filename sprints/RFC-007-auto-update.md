# RFC-007 — Auto-Update via GitHub Releases

**Sprint** : 4 (Semaine 7-8)
**Priorite** : P1
**Dependances** : Aucune (feature standalone)
**References CDC** : Hors perimetre v1 — nouvelle feature

---

## Contexte

Aujourd'hui l'utilisateur doit manuellement telecharger le `.zip` depuis la page GitHub Releases, supprimer l'ancienne version et re-glisser l'app dans `/Applications`. Ce flow est penible et freine l'adoption des mises a jour.

**Objectif** : L'app detecte automatiquement qu'une nouvelle version est disponible, notifie l'utilisateur via le notch, et installe la mise a jour sans quitter le navigateur ni aller sur GitHub.

## Analyse des options

| Approche | Avantages | Inconvenients | Verdict |
|----------|-----------|---------------|---------|
| **Sparkle** (framework macOS standard) | Battle-tested, delta updates, signature check, UI native, support appcast + GitHub | Dependance externe (~2MB), config initiale | **Retenu** |
| Custom GitHub API poller | Zero dependance, controle total | Reinventer la roue (signature, install, rollback), maintenance lourde | Rejete |
| macOS App Store | Distribution native, auto-update gratuit | Review Apple, restrictions sandboxing, pas adapte a notre use case | Hors scope |

### Pourquoi Sparkle

[Sparkle](https://sparkle-project.org/) est le standard de facto pour l'auto-update des apps macOS distribuees hors App Store. Il est utilise par Firefox, Signal Desktop, iTerm2, etc.

Sparkle supporte nativement :
- **Appcast XML** : flux RSS decrivant les versions disponibles (hebergeable sur GitHub Pages ou en raw dans le repo)
- **Verification de signature** : EdDSA (ed25519) — s'assure que le binaire vient bien de nous
- **Install automatique** : remplacement du .app bundle, relaunch
- **Delta updates** : patches binaires pour reduire la taille du download (optionnel)
- **UI de notification** : fenetre native "Update available" avec release notes

### Integration avec le pipeline existant

Le `Makefile` produit deja un `.zip` signe et notarise. Il faut ajouter :

1. **Generation de l'appcast** : `generate_appcast` (outil CLI fourni par Sparkle)
2. **Signature EdDSA** : cle privee stockee en local (jamais committee), cle publique dans le bundle
3. **Upload** : le `.zip` + `appcast.xml` sont publies dans la GitHub Release

```
make release (existant)
  → build → sign → notarize → staple → zip
  
make release (mis a jour)
  → build → sign → notarize → staple → zip
  → sign zip avec EdDSA (Sparkle)
  → generate appcast.xml
  → gh release create vX.Y.Z oc-notch.zip appcast.xml
```

## Decision technique

### Architecture

```
App Launch
  │
  ├─ SUUpdater.checkForUpdatesInBackground()
  │    → Fetch appcast.xml depuis GitHub (raw URL ou Release asset)
  │    → Compare CFBundleShortVersionString local vs appcast
  │
  ├─ Si nouvelle version disponible :
  │    → Sparkle affiche fenetre native "Update Available"
  │    → OU (optionnel) : on intercepte le callback pour notifier via le notch
  │
  └─ User clique "Install Update"
       → Sparkle telecharge le .zip
       → Verifie signature EdDSA
       → Remplace le .app bundle
       → Relaunch l'app
```

### Notification via le notch (option UX recommandee)

Au lieu d'utiliser la fenetre Sparkle standard, on peut intercepter `SPUUpdaterDelegate` pour :
1. Recevoir le callback "update disponible"
2. Afficher une notification dans le notch (meme pattern que RFC-005)
3. Bouton "Mettre a jour" lance le flow Sparkle

```
┌──────────────────────────────────────────┐
│  [Avatar]  ███ NOTCH ███  [3 sessions]   │
├──────────────────────────────────────────┤
│  ⬆ OC-Notch v1.2.0 disponible           │
│  "Ajout auto-update + corrections"       │
│                                          │
│  [Mettre a jour]  [Plus tard]            │
└──────────────────────────────────────────┘
```

### Appcast hosting

**Option retenue** : appcast.xml en tant qu'asset de la GitHub Release.

URL stable : `https://github.com/Jay-Qiu/OC-notch/releases/latest/download/appcast.xml`

Sparkle est configure avec cette URL dans `Info.plist` :
```xml
<key>SUFeedURL</key>
<string>https://github.com/Jay-Qiu/OC-notch/releases/latest/download/appcast.xml</string>
```

### Frequence de check

- Au lancement de l'app
- Puis toutes les 6 heures (configurable via `SUScheduledCheckInterval`)
- Check manuel via futur menu "Chercher une mise a jour"

### Gestion de la cle EdDSA

```bash
# Generation (une seule fois, jamais commitee)
./bin/generate_keys  # fourni par Sparkle

# Cle publique → dans Info.plist
<key>SUPublicEDKey</key>
<string>base64-encoded-public-key</string>

# Cle privee → dans Keychain ou fichier local ignore par .gitignore
# Utilisee par generate_appcast lors du make release
```

## Taches

- [ ] Ajouter Sparkle comme dependance (SPM ou vendored framework)
- [ ] Generer une paire de cles EdDSA, stocker la publique dans Info.plist
- [ ] Configurer `SUFeedURL` dans Info.plist
- [ ] Initialiser `SPUUpdater` dans `AppDelegate` avec check au lancement
- [ ] Implementer `SPUUpdaterDelegate` pour intercepter les callbacks
- [ ] (Optionnel) Afficher la notification de MaJ dans le notch au lieu de la fenetre Sparkle
- [ ] Mettre a jour le `Makefile` : signer le zip avec EdDSA, generer appcast.xml
- [ ] Mettre a jour le flow `gh release create` pour inclure appcast.xml
- [ ] Documenter la procedure de release mise a jour dans README
- [ ] Tester le cycle complet : publier release → app detecte → installe → relaunch

## Criteres d'acceptation

1. L'app detecte une nouvelle version disponible en < 30s apres le lancement
2. L'utilisateur est notifie (fenetre Sparkle ou notification notch)
3. Clic "Mettre a jour" → download + install + relaunch sans intervention manuelle
4. La signature EdDSA est verifiee avant installation (pas d'install si signature invalide)
5. Le flow ne bloque PAS l'utilisation de l'app pendant le download
6. `make release` genere automatiquement l'appcast.xml et publie tous les assets
7. Aucune cle privee n'est committee dans le repo

## Risques

| Risque | Severite | Mitigation |
|--------|----------|------------|
| Sparkle incompatible Swift 6 strict concurrency | Moyenne | Verifier la compatibilite avant integration. Sparkle 2.x supporte Swift concurrency. |
| GitHub rate limit sur les checks d'appcast | Faible | Interval de 6h + cache ETag/Last-Modified |
| Utilisateur sans connexion internet | Faible | Check silencieux, pas d'erreur affichee. Retry au prochain cycle. |
| Conflit avec la notarization Apple | Faible | Sparkle gere nativement les apps notarisees |
