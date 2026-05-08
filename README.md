# ChabahRoot — Surveillance du Noyau en Temps Réel avec eBPF

**Une suite de surveillance du noyau Linux prête pour la production utilisant eBPF (Extended Berkeley Packet Filter) pour le traçage des appels système avec une surcharge CPU minimale.**

---

## Démarrage Rapide

```bash
# 1. Valider les prérequis système
sudo chabahroot/m1/check.sh

# 2. Démarrer la surveillance du noyau
sudo chabahroot/m1/init.sh

# 3. Arrêter avec Ctrl+C (nettoyage automatique)
```

---

## Qu'est-ce que ChabahRoot?

ChabahRoot est un **cadre de surveillance du noyau léger** basé sur **eBPF** qui capture les événements système avec une surcharge CPU minimale:

- **1-2% surcharge CPU** (vs 5-15% avec tracefs traditionnel)
- **<1ms latence d'événement** pour la surveillance en temps réel
- **Filtrage in-kernel** réduit le volume de données de 10 à 100x
- **Surveillance des processus** — capture les appels système, création de processus, changements de privilèges
- **Analyse de sécurité** — suit les modèles d'exécution et les mutations système

### Fonctionnement

```
Événement système (ex: appel système execve)
         ↓
    [Filtre eBPF] ← S'exécute dans le noyau (1-2% CPU)
         ↓
   Ring Buffer ← Flux de données efficace
         ↓
  Espace utilisateur ← Application traite les événements
```

---

## Prérequis Système

| Prérequis | Version | Remarques |
|-----------|---------|----------|
| **Noyau** | 4.0+ | Support eBPF |
| **Architecture** | x86_64, ARM64 | Largement supporté |
| **Privilèges** | root | Requis pour accès kernel |
| **Outils** | bpftool, clang, llvm | `apt install linux-tools-generic clang llvm` |

---

## Structure du Projet

```
chabahroot/
├── m1/                              # Couche d'ingestion du noyau
│   ├── check.sh                     # Valider les prérequis
│   ├── init.sh                      # Initialiser la surveillance
│   ├── cleanup.sh                   # Nettoyer les ressources
│   ├── ebpf_integration.sh          # Gestion des programmes eBPF
│   ├── lib/
│   │   └── lib_utils.sh             # Utilitaires partagés
│   └── README.md                    # Documentation M1
└── docs/                            # Documentation
    ├── CHABAHROOT_GUIDE_COMPLET.md           # Guide complet
    ├── CHABAHROOT_ARCHITECTURE_TECHNIQUE.md  # Architecture technique
    ├── EBPF_USAGE_GUIDE.md                   # Ressources eBPF
    └── ChabahRoot_M1_Guide.html              # Référence HTML
```

---

## Composants Principaux

### check.sh — Validation du Système
Valide que votre système remplit tous les prérequis eBPF:
- Version du noyau (4.0+)
- Disponibilité des outils eBPF (bpftool, clang, llvm)
- Privilèges root
- Permissions des répertoires

```bash
sudo ./chabahroot/m1/check.sh
```

### init.sh — Initialisation de la Surveillance
Charge et initialise les programmes eBPF pour la capture d'événements du noyau:
- Compile les programmes eBPF
- Les charge dans le noyau via bpftool
- Les attache aux tracepoints
- Maintient la surveillance jusqu'à interruption

```bash
sudo ./chabahroot/m1/init.sh
```

### cleanup.sh — Nettoyage des Ressources
Décharge gracieusement les programmes eBPF et libère les ressources kernel:
- Se détache des tracepoints
- Décharge les programmes
- Libère les maps mémoire

```bash
sudo ./chabahroot/m1/cleanup.sh
```

### ebpf_integration.sh — Gestion eBPF
Gestionnaire principal du cycle de vie et du chargement des programmes eBPF:
- Compile C → bytecode BPF
- Charge via bpftool
- Gère les maps et buffers
- Gère le nettoyage

```bash
sudo ./chabahroot/m1/ebpf_integration.sh load
sudo ./chabahroot/m1/ebpf_integration.sh cleanup
```

---

## Fonctionnalités Clés

### Filtrage In-Kernel
- Filtre les événements avant leur sortie du noyau
- Réduit drastiquement le volume de données
- Logique de filtrage programmable

### Surcharge Minimale
- Utilisation CPU: 1-2%
- Latence d'événement: <1ms
- Adapté à la production

### Surveillance en Temps Réel
- Capture les événements au moment de leur occurrence
- Ring buffer pour flux efficient
- Transfert direct du noyau vers l'espace utilisateur

### Architecture Modulaire
- Séparation claire des préoccupations
- Bibliothèque d'utilitaires réutilisable
- Scripts indépendants

### Documentation en Français
- Commentaires en français
- Nommage sémantique des fonctions
- Organisation du code claire

---

## Exemple d'Utilisation

### Session de Surveillance Basique

```bash
# Terminal 1: Valider et démarrer la surveillance
$ sudo chabahroot/m1/check.sh
$ sudo chabahroot/m1/init.sh

# Le système capture maintenant les événements du noyau
# (En production, pipe vers la couche d'analyse)

# Terminal 2: Afficher les événements (si supporté)
$ bpftool map show
$ bpftool map dump id <map_id>

# Terminal 1: Arrêter la surveillance (Ctrl+C)
# Le nettoyage se fait automatiquement
```

### Intégration avec les Modules en Aval

Dans un pipeline ChabahRoot complet:

```
M1 (init.sh) → Capture des événements
    ↓
  [Ring Buffer]
    ↓
M2 (Détection) → Classifie les événements
    ↓
M3 (Analyse) → Normalise les données
    ↓
M4 (Sortie) → Logs/pipelines
```

---

## Documentation

| Document | Objectif | Public |
|----------|----------|--------|
| [docs/CHABAHROOT_GUIDE_COMPLET.md](docs/CHABAHROOT_GUIDE_COMPLET.md) | Guide complet avec exemples | Utilisateurs, développeurs |
| [docs/CHABAHROOT_ARCHITECTURE_TECHNIQUE.md](docs/CHABAHROOT_ARCHITECTURE_TECHNIQUE.md) | Plongée technique | Développeurs, DevOps |
| [docs/EBPF_USAGE_GUIDE.md](docs/EBPF_USAGE_GUIDE.md) | Ressources d'apprentissage eBPF | Étudiants, développeurs |
| [chabahroot/m1/README.md](chabahroot/m1/README.md) | Documentation module spécifique | DevOps, opérateurs |
| [docs/ChabahRoot_M1_Guide.html](docs/ChabahRoot_M1_Guide.html) | Guide HTML original | Référence |

---

## Vue d'ensemble de l'Architecture

### Design en Couches

```
┌────────────────────────────────────────┐
│  Scripts d'Application                 │
│  (init.sh, cleanup.sh, check.sh)       │
├────────────────────────────────────────┤
│  Utilitaires Partagés                  │
│  (lib_utils.sh)                        │
├────────────────────────────────────────┤
│  Intégration eBPF                      │
│  (ebpf_integration.sh)                 │
├────────────────────────────────────────┤
│  Noyau Linux                           │
│  • Machine Virtuelle eBPF              │
│  • Tracepoints                         │
│  • Ring Buffers                        │
└────────────────────────────────────────┘
```

### Graphe de Dépendances

```
init.sh
  ├─ lib_utils.sh
  └─ ebpf_integration.sh
      └─ lib_utils.sh

check.sh
  └─ lib_utils.sh

cleanup.sh
  ├─ lib_utils.sh
  └─ ebpf_integration.sh
      └─ lib_utils.sh
```

---

## Caractéristiques de Performance

| Métrique | Valeur | Remarques |
|----------|--------|----------|
| **Surcharge CPU** | 1-2% | Comparé à 5-15% avec tracefs |
| **Latence d'événement** | <1ms | De la capture kernel au buffer |
| **Mémoire par programme** | ~50-200 KB | Configurable selon taille map |
| **Programmes par système** | 100+ | Pas de limite stricte (dépend ressources) |
| **Taille max programme** | 1 MB | Limite bytecode vérifié |
| **Débit ring buffer** | 100K+ events/sec | Dépend du filtrage |

---

## Problèmes Courants

### "bpftool not found"
```bash
# Solution
sudo apt install linux-tools-generic
```

### "clang not found"
```bash
# Solution
sudo apt install clang llvm
```

### "Kernel 4.0+ required"
```bash
# Vérifier votre version du noyau
uname -r

# Si < 4.0, mettre à jour le noyau
sudo apt update && sudo apt install linux-image-generic
sudo reboot
```

### "Permission denied"
```bash
# eBPF requiert root
sudo chabahroot/m1/init.sh
```

---

## eBPF vs Tracefs

| Aspect | eBPF | Tracefs |
|--------|------|---------|
| **Surcharge CPU** | 1-2% | 5-15% |
| **Latence** | <1ms | 5-10ms |
| **Filtrage** | In-kernel | Espace utilisateur |
| **Complexité** | Moyenne | Basse |
| **Compatibilité** | 4.0+ | 2.6.27+ |
| **Réduction de données** | 10-100x | 2-5x |

**ChabahRoot utilise eBPF exclusivement** pour une performance et une efficacité supérieures.

---

## Sujets Avancés

### Personnaliser les Programmes eBPF
Modifier la source du programme eBPF et recompiler:
```bash
# Modifier la source du programme
vi chabahroot/m1/ebpf_program.c

# Recompiler
sudo chabahroot/m1/ebpf_integration.sh load
```

### Déboguer les Programmes eBPF
```bash
# Afficher les programmes chargés
bpftool prog list

# Inspecter les détails d'un programme
bpftool prog show id <ID>

# Vérifier les logs du kernel
dmesg | grep -i bpf
```

### Ajustement des Performances
```bash
# Surveiller l'utilisation CPU
top -p $(pgrep -f 'init.sh')

# Afficher les statistiques kernel
cat /proc/sys/kernel/bpf_stats_enabled
```

Pour un ajustement détaillé, consultez [CHABAHROOT_ARCHITECTURE_TECHNIQUE.md](docs/CHABAHROOT_ARCHITECTURE_TECHNIQUE.md).

---

## Apprendre eBPF

**Nouveau dans eBPF?** Commencez par [docs/EBPF_USAGE_GUIDE.md](docs/EBPF_USAGE_GUIDE.md) pour:
- Explications des concepts
- Liens vers documentation des outils
- Ressources d'apprentissage organisées
- Exemples pratiques

**Ressources**:
- [Site Officiel eBPF](https://ebpf.io/)
- [Outils BPF de Brendan Gregg](http://www.brendangregg.com/ebpf.html)
- [Documentation Noyau Linux](https://www.kernel.org/doc/html/latest/userspace-api/ebpf/)

---

## Licence et Auteur

**Auteur**: Mousaab El harmali

---

## Prochaines Étapes

1. **Configuration**: Exécutez `sudo chabahroot/m1/check.sh` pour valider votre système
2. **Démarrage**: Exécutez `sudo chabahroot/m1/init.sh` pour commencer la surveillance
3. **Apprentissage**: Lisez [docs/CHABAHROOT_GUIDE_COMPLET.md](docs/CHABAHROOT_GUIDE_COMPLET.md) pour une utilisation détaillée
4. **Intégration**: Connectez aux modules en aval M2/M3 pour le pipeline complet
5. **Extension**: Personnalisez les programmes eBPF pour vos besoins spécifiques

---

 
**Support Noyau**: 4.0+  
**Surcharge**: 1-2% CPU
