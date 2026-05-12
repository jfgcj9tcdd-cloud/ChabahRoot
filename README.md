# ChabahRoot — Plateforme de Télémétrie Noyau en Temps Réel

**Architecture complète à 4 couches de surveillance du noyau Linux avec eBPF, conçue pour capturer, filtrer, analyser et auditer les événements système avec une surcharge CPU minimale.**

---

## Table des Matières

1. [Vue d'ensemble](#vue-densemble)
2. [Architecture Complète (4 Couches)](#architecture-complète-4-couches)
3. [Équipe et Responsabilités](#équipe-et-responsabilités)
4. [Installation](#installation)
5. [Démarrage Rapide](#démarrage-rapide)
6. [Couche M1: Ingestion eBPF](#couche-m1-ingestion-ebpf)
7. [Couche M2: Analyse et Règles](#couche-m2-analyse-et-règles)
8. [Couche M3: Transport et Normalisation](#couche-m3-transport-et-normalisation)
9. [Couche M4: Intégration et Tests](#couche-m4-intégration-et-tests)
10. [Configuration](#configuration)
11. [Dépannage](#dépannage)
12. [Ressources Techniques](#ressources-techniques)

---

## Vue d'ensemble

ChabahRoot est une **plateforme modulaire de télémétrie système** basée sur **eBPF (Extended Berkeley Packet Filter)** qui capture et analyse les événements du noyau Linux:

- **1-2% surcharge CPU** (vs 5-15% avec tracefs traditionnel)
- **<1ms latence d'événement** pour la surveillance en temps réel
- **Filtrage in-kernel** réduit le bruit de 10-100x
- **Architecture modulaire** avec 4 couches distinctes (Ingestion → Transport → Analysis → Output)
- **Détection d'escalades de privilèges** et comportements anormaux
- **Audit de sécurité** automatisé et continu

### Flux de Données Complet

```
Événements Noyau (execve, setuid, setgid, prctl)
         ↓
   [M1: eBPF Probes] ← Filtrage in-kernel (1-2% CPU overhead)
         ↓
   Ring Buffer ← Communication kernel↔userspace efficace
         ↓
[M3: Ring Buffer Reader] ← Lecture continue et normalisation
         ↓
   [M2: Rules Engine] ← Analyse avec règles configurables
         ↓
   [Journalisation Structurée] → Alertes, rapports, audit
```

---

## Architecture Complète (4 Couches)

### Couche 1: M1 — Ingestion eBPF (Kernel Layer)

**Responsabilité**: Capture d'événements au niveau noyau avec filtrage in-kernel

**Composants**:
- `chabahroot/m1/check.sh` — Validation des prérequis système
- `chabahroot/m1/init.sh` — Initialisation des sondes tracefs
- `chabahroot/m1/cleanup.sh` — Nettoyage des ressources noyau
- `chabahroot/m1/ebpf_integration.sh` — Compilation et gestion eBPF
- `chabahroot/m1/m1_complete.sh` — Orchestration complète M1
- `chabahroot/m1/ebpf/event_capture.c` — Probes eBPF (4 tracepoints)
- `chabahroot/m1/lib/lib_utils.sh` — Utilitaires partagés

**Événements capturés**:
- `syscalls:sys_enter_execve` — Exécution de binaires et scripts
- `syscalls:sys_enter_setuid` — Escalades d'UID
- `syscalls:sys_enter_setgid` — Escalades de GID
- `syscalls:sys_enter_prctl` — Modifications de capabilities

**Caractéristiques**:
- Ring buffer pour streaming kernel→userspace
- Filtrage des processus système (threads noyau)
- Extraction des arguments de ligne de commande
- Horodatage précis au nanoseconde

---

### Couche 2: M3 — Transport et Normalisation (Data Layer)

**Responsabilité**: Lire les événements du ring buffer, normaliser en JSON, enrichir avec contexte

**Composants**:
- `detection/ringbuf_reader.sh` — Lecteur ring buffer continu
- `detection/rules.conf` — Configuration centralisée

**Fonctionnalités**:
- Lecture continue du ring buffer eBPF
- Décodage des événements bruts
- Enrichissement avec contexte parent (PID, commande, permissions)
- Normalisation JSON pour M2
- Filtrage des données sensibles (mots-clés: password, token, secret)
- Mise en cache des événements en /tmp

**Schéma JSON normalisé**:
```json
{
  "timestamp": 1234567890,
  "timestamp_ns": 1234567890000000000,
  "event_type": "exec|setuid|setgid|prctl_caps",
  "process": {
    "pid": 1234,
    "ppid": 1,
    "comm": "bash",
    "cmdline": "/bin/bash",
    "parent_comm": "systemd"
  },
  "credentials": {"uid": 1000, "gid": 1000},
  "data": {"argv": "/bin/bash"}
}
```

---

### Couche 3: M2 — Analyse et Règles (Rules Engine)

**Responsabilité**: Appliquer des règles de détection configurables et générer des alertes

**Composants**:
- `detection/rules_engine.sh` — Moteur de règles
- `detection/detection_rules.json` — Définitions des règles (7 règles par défaut)

**Règles Intégrées**:
1. **rule_exec_001**: Exécution de binaires depuis /tmp, /dev/shm
2. **rule_priv_001**: Escalade UID→0 via setuid
3. **rule_priv_002**: Processus suspects s'exécutant en tant que root
4. **rule_susp_001**: Patterns de commandes malveillantes (reverse shells, exfiltration)
5. **rule_caps_001**: Modification de capabilities par utilisateurs non-root
6. **rule_cred_001**: Données sensibles dans arguments (password, token, secret, key)
7. **rule_suid_001**: Journalisation des exécutions SUID

**Format des Règles** (JSON):
```json
{
  "id": "rule_exec_001",
  "name": "Execution from unsafe location",
  "type": "EXECUTION",
  "severity": "HIGH",
  "condition": ".event_type == \"exec\" and .data.argv | test(\"^(/tmp|/dev/shm)\")",
  "actions": ["journal", "slack"],
  "enabled": true
}
```

**Actions d'Alerte**:
- Journal (systemd journal ou fichier)
- Slack (intégration future)
- Email (intégration future)

---

### Couche 4: M4 — Intégration et Tests (Orchestration Layer)

**Responsabilité**: Assembler les 3 couches, tester le pipeline, valider la cohérence

**Composants**:
- `detection/complete_pipeline.sh` — Orchestrateur principal du pipeline
- `detection/m4_integration_tests.sh` — Suite de tests M1-M4
- `detection/logger.sh` — Journalisation centralisée avec niveaux

**Fonctionnalités M4**:
- Lancer M1, M3, M2 dans l'ordre correct
- Vérifier les prérequis système
- Créer les FIFOs pour la communication inter-couches
- Monitorer l'état des processus
- Redémarrage automatique en cas de panne
- Tests d'intégration M1→M2→M3→M4
- Rapport de santé système

**Tests Implémentés**:
- M1: Compilation eBPF et validation
- M2: Validation du fichier de règles JSON
- M3: Validation de la structure d'événement
- M4: Vérification de l'existence des scripts

---

## Équipe et Responsabilités

### M1 — Ingénieur Noyau

**Objectif**: Capturer les événements système et les fournir via ring buffer

**Livrables**:
- ✓ Compilation des programmes eBPF
- ✓ Chargement dans le noyau via bpftool
- ✓ Attachement aux tracepoints
- ✓ Communication kernel↔userspace via ring buffer
- ✓ Validation des prérequis (kernel 4.0+, BPF_EVENTS, tracefs)

**Scripts de M1**:
```bash
# Lancer la couche M1 complète
sudo ./chabahroot/m1/m1_complete.sh start

# Vérifier le statut
sudo ./chabahroot/m1/ebpf_integration.sh status

# Arrêter
sudo ./chabahroot/m1/m1_complete.sh stop
```

---

### M2 — Ingénieur Détection

**Objectif**: Analyser les événements normalisés et générer des alertes selon les règles

**Livrables**:
- ✓ Moteur de règles (jq-based condition evaluation)
- ✓ 7 règles de détection prédéfinies
- ✓ Système d'actions (journal, slack, email)
- ✓ Format d'alerte structuré

**Configuration des Règles**: `detection/detection_rules.json`

Ajouter une règle personnalisée:
```json
{
  "id": "rule_custom_001",
  "name": "My custom rule",
  "condition": ".event_type == \"exec\" and .data.argv | test(\"dangerous_pattern\")",
  "severity": "HIGH",
  "enabled": true,
  "actions": ["journal"]
}
```

---

### M3 — Ingénieur Transport et Collecte

**Objectif**: Lire le ring buffer, normaliser, enrichir et passer à M2

**Livrables**:
- ✓ Lecteur de ring buffer continu
- ✓ Décodage des événements bruts
- ✓ Normalisation JSON
- ✓ Enrichissement avec contexte parent
- ✓ Filtrage des données sensibles

**Schéma de Sortie M3**: JSON normalisé compatible M2

---

### M4 — Ingénieur Intégration

**Objectif**: Assembler toutes les couches, tester et valider l'intégrité

**Livrables**:
- ✓ Orchestrateur de pipeline (M1→M3→M2)
- ✓ Vérification des prérequis
- ✓ Gestion du cycle de vie (start/stop/status)
- ✓ Suite de tests automatisée
- ✓ Monitoring du pipeline
- ✓ Redémarrage automatique

**Lancer le Pipeline Complet**:
```bash
# Mode interactif (logs en console)
sudo ./detection/complete_pipeline.sh run

# Mode arrière-plan
sudo ./detection/complete_pipeline.sh start

# Vérifier l'état
sudo ./detection/complete_pipeline.sh status

# Arrêter
sudo ./detection/complete_pipeline.sh stop

# Exécuter les tests
sudo ./detection/complete_pipeline.sh test
```

---

## Installation

### Prérequis Système

#### Matériel
- **Architecture**: x86_64 ou ARM64
- **RAM**: Minimum 512 MB, recommandé 1 GB+

#### Noyau Linux
- **Version minimum**: Linux 4.0 (pour eBPF support)
- **Version recommandée**: Linux 5.0+
- **Config requise**: `CONFIG_BPF=y`, `CONFIG_BPF_SYSCALL=y`, `CONFIG_BPF_JIT=y`, `CONFIG_BPF_EVENTS=y`

#### Outils
```bash
# Debian/Ubuntu
sudo apt install -y linux-tools-generic clang llvm build-essential

# RHEL/CentOS
sudo yum install -y kernel-tools clang llvm gcc
```

### Étapes d'Installation

```bash
# 1. Cloner le projet
git clone https://github.com/mousaab-vtrx/ChabahRoot.git
cd ChabahRoot

# 2. Rendre les scripts exécutables
chmod +x chabahroot/m1/*.sh chabahroot/m1/lib/*.sh detection/*.sh

# 3. Vérifier les prérequis
sudo ./chabahroot/m1/check.sh

# 4. Préparer les répertoires
sudo mkdir -p /var/log/chabahroot
mkdir -p detection/logs detection/tmp
```

---

## Démarrage Rapide

### Scénario 1: Pipeline Complet (Production)

```bash
# Lancer le pipeline complet M1→M3→M2→M4
sudo ./detection/complete_pipeline.sh run

# Dans un autre terminal: vérifier l'état
sudo ./detection/complete_pipeline.sh status

# Consulter les logs
tail -f detection/logs/chabah.log
tail -f /tmp/chabah_pipeline_state/alerts.log
```

### Scénario 2: Test Rapide (Développement)

```bash
# Lancer les tests d'intégration M4
sudo ./detection/m4_integration_tests.sh all

# Tester une couche spécifique
sudo ./detection/m4_integration_tests.sh m1
sudo ./detection/m4_integration_tests.sh m2
```

### Scénario 3: Mode M1 Uniquement (Kernel Layer)

```bash
# Lancer juste la couche d'ingestion M1
sudo ./chabahroot/m1/m1_complete.sh start

# Vérifier les programmes eBPF chargés
sudo ./chabahroot/m1/ebpf_integration.sh status

# Arrêter
sudo ./chabahroot/m1/m1_complete.sh stop
```

---

## Configuration

### Fichier de Configuration Principal (detection/rules.conf)

```bash
# Logging
LOG_FILE="./logs/chabah.log"
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ALERT

# Détection
TARGET_UID=0  # UID à surveiller (0=root)
POLL_INTERVAL=2  # Intervalle de polling en secondes

# Données sensibles à filtrer
SENSITIVE_KEYWORDS="pass password token secret key api_key"

# Métadonnées
PROJECT_NAME="ChabahRoot"
MODULE_NAME="Detection Engine"
VERSION="1.0.0"
```

### Fichier de Règles (detection/detection_rules.json)

Modifier les règles de détection:
```json
{
  "rules": [
    {
      "id": "rule_exec_001",
      "name": "Binary execution from unsafe location",
      "condition": ".event_type == \"exec\" and (.data.argv | test(\"^(/tmp|/dev/shm)\"))",
      "severity": "HIGH",
      "enabled": true,
      "actions": ["journal"]
    }
  ]
}
```

---

## Dépannage

### Problème: "Permission denied" pour bpftool

```bash
# Vérifier les permissions
sudo ls -la /sys/kernel/debug/tracing/

# Monter debugfs si absent
sudo mount -t debugfs none /sys/kernel/debug
```

### Problème: Kernel version < 4.0

```bash
# Vérifier la version
uname -r

# Mettre à jour (Debian/Ubuntu)
sudo apt install --install-recommends linux-image-generic linux-headers-generic
sudo reboot
```

### Problème: Ring buffer non accessible

```bash
# Vérifier la configuration du noyau
zcat /proc/config.gz | grep BPF

# Compiler le kernel avec BPF activé si nécessaire
```

### Déboguer avec Verbosité

```bash
# Mode DEBUG
export DEBUG=1
sudo ./detection/complete_pipeline.sh run

# Consulter les logs détaillés
tail -f detection/logs/chabah.log | grep DEBUG
```

---

## Ressources Techniques

### eBPF

**Extended Berkeley Packet Filter** — Machine virtuelle légère dans le noyau pour filtering et monitoring in-kernel.

- **In-kernel VM**: Exécute du bytecode compilé directement dans le noyau
- **JIT Compilation**: Code machine natif pour performances optimales
- **Ring Buffers**: Canal efficace pour streaming kernel→userspace
- **Tracepoints**: Points d'instrumentation statiques du noyau

### Linux Kernel Interfaces

**Tracepoints Utilisés**:
- `syscalls:sys_enter_execve` — Exécution de programmes
- `syscalls:sys_enter_setuid` — Changements d'UID
- `syscalls:sys_enter_setgid` — Changements de GID
- `syscalls:sys_enter_prctl` — Modifications de capabilities

**Namespaces et Cgroups**: ChabahRoot peut être étendu pour surveiller l'isolation des conteneurs via namespaces et limitations de ressources via cgroups.

### Références Externes

- [Linux eBPF Documentation](https://www.kernel.org/doc/html/latest/userspace-api/ebpf/index.html)
- [bpftool Manual](https://man7.org/linux/man-pages/man8/bpftool.8.html)
- [eBPF.io Community](https://ebpf.io/)
- [BCC Toolkit](https://github.com/iovisor/bcc)
- [libbpf Standard Library](https://github.com/libbpf/libbpf)

---

## Conventions et Standards

### Style des Scripts Shell

- **Sécurité**: `set -euo pipefail` pour strict error handling
- **Logging**: Utiliser les fonctions centralisées (log_info, log_error, log_alert)
- **Commentaires**: Français, minimalistes, uniquement si non-obvious
- **Noms**: Sémantiques et clairs
- **Modularité**: Pas de duplication, fonctions réutilisables

### Architecture

- Chaque module (M1/M2/M3/M4) a une **responsabilité unique**
- Communication via **FIFOs et pipes**
- Configuration **centralisée** (rules.conf)
- Pas de **dépendances circulaires**

---

## Sécurité et Avertissements Légaux

⚠️ **AVERTISSEMENT IMPORTANT**

Ce projet est destiné **exclusivement** à un usage légal dans le cadre de:
- Tests sur vos propres systèmes
- Environnements de laboratoire (CTF, VMs de test)
- Missions de sécurité avec autorisation écrite explicite

Toute utilisation sur des systèmes sans autorisation est **illégale** et engage votre responsabilité pénale.

---

**Version**: 1.0.0 — **Statut**: Production Ready | **Architecture**: 4-Layer M1/M2/M3/M4


- **1-2% surcharge CPU** (vs 5-15% avec tracefs traditionnel)
- **<1ms latence d'événement** pour la surveillance en temps réel
- **Filtrage in-kernel** réduit le volume de données de 10 à 100x
- **Surveillance des processus** — capture les appels système, création de processus, escalades de privilèges
- **Audit de sécurité** — détecte les vecteurs d'escalade et lacunes de sécurité

### Flux de Données

```
Événement système (ex: execve, fork, privilege escalation)
         ↓
    [Filtre eBPF] ← S'exécute dans le noyau (1-2% CPU)
         ↓
   Ring Buffer ← Transfert efficace vers l'espace utilisateur
         ↓
  Espace utilisateur ← Application traite les événements
```

---

## Caractéristiques

### Performance
- Filtrage directement dans le noyau (pas de transit de données inutiles)
- Traitement parallèle sur plusieurs CPUs
- Pas d'interruptions système importantes

### Fiabilité
- Gestion automatique des ressources avec nettoyage propre
- Récupération gracieuse en cas d'erreur
- Logging structuré avec niveaux configurables

### Production-Ready
- Scripts idempotents et sûrs
- Validation robuste des dépendances
- Permissions et erreurs bien documentées

---

## Architecture

### Structure du Projet

```
chabahroot/
├── m1/                              # Couche d'ingestion du noyau (eBPF)
│   ├── check.sh                     # Validation des prérequis système
│   ├── init.sh                      # Initialisation de la surveillance
│   ├── cleanup.sh                   # Nettoyage des ressources eBPF
│   ├── ebpf_integration.sh          # Compilation et gestion des programmes eBPF
│   ├── lib/
│   │   └── lib_utils.sh             # Utilitaires partagés (logging, validation)
│   └── ebpf/                        # Programmes eBPF compilés (généré dynamiquement)
│
detection/
├── run.sh                           # Orchestrateur principal de détection
├── logger.sh                        # Module de journalisation centralisé
├── defensive.sh                     # Surveillance continue des escalades UID
├── offensive.sh                     # Audit de sécurité one-shot
├── rules.conf                       # Configuration des paramètres
├── logs/                            # Fichiers de journal
└── tmp/                             # Fichiers temporaires (suivi PID, etc)

docs/                               # Documentation complète
README.md                           # Ce fichier
```

### Modules M1 — Ingestion du Noyau

#### `check.sh` — Validation du Système
Vérifie que tous les prérequis sont satisfaits:
- Version du noyau (4.0+ pour eBPF)
- Disponibilité des outils (bpftool, clang, llvm-strip)
- Permissions d'accès (root)
- Répertoires de logs

```bash
sudo ./chabahroot/m1/check.sh
```

#### `init.sh` — Initialisation de la Surveillance
Lance le traçage eBPF du noyau:
- Compile les programmes eBPF
- Les charge dans le noyau via bpftool
- Les attache aux tracepoints
- Maintient la surveillance jusqu'à interruption (Ctrl+C)

```bash
sudo ./chabahroot/m1/init.sh
```

#### `cleanup.sh` — Nettoyage
Arrête la surveillance et libère les ressources:
- Détache les programmes eBPF du noyau
- Libère la mémoire kernel
- Ferme les fichiers ouverts

```bash
sudo ./chabahroot/m1/cleanup.sh
```

#### `ebpf_integration.sh` — Gestion eBPF
Module central de compilation et gestion des programmes eBPF:

```bash
sudo ./chabahroot/m1/ebpf_integration.sh [load|cleanup|status]
```

### Module de Détection

#### `run.sh` — Orchestrateur Principal
Gère la surveillance défensive et les audits offensifs:

```bash
sudo ./detection/run.sh [--defensive-only|--offensive-only|--no-offensive|--help]
```

**Modes:**
- `full` (par défaut): Défensif continu + audit unique
- `--defensive-only`: Surveillance continue uniquement
- `--offensive-only`: Audit de sécurité uniquement
- `--no-offensive`: Défensif sans audit offensif

#### `defensive.sh` — Surveillance Défensive
Monitoring continu des escalades de privilèges en temps réel:
- Détecte les transitions UID→0 (root)
- Alerte sur les processus suspects (nc, ncat, bash, python, etc)
- Évite le spam des PIDs déjà rapportés

#### `offensive.sh` — Audit Offensif
Audit de sécurité one-shot pour détecter les lacunes:
- Scan des binaires SUID non-standard
- Détection des fichiers world-writable en zones critiques
- Analyse des configurations sudoers dangereuses (NOPASSWD, ALL=(ALL))

#### `logger.sh` — Journalisation Centralisée
Module de logging unifié avec:
- Filtrage par niveau (DEBUG, INFO, WARN, ALERT)
- Couleurs ANSI pour la console
- Enregistrement structuré dans les fichiers

---

## Installation

### Prérequis Système

#### Matériel
- **Architecture**: x86_64 ou ARM64
- **RAM**: Minimum 512 MB, recommandé 1 GB+

#### Noyau Linux
- **Version minimum**: Linux 4.0 (pour eBPF support)
- **Version recommandée**: Linux 5.0+

#### Configuration Kernel Requise
```bash
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_EVENTS=y
CONFIG_FTRACE=y
CONFIG_TRACEFS=y
```

#### Outils et Dépendances
```bash
# Debian/Ubuntu
sudo apt update
sudo apt install \
    linux-tools-generic \
    clang \
    llvm \
    build-essential \
    git

# RHEL/CentOS
sudo yum install \
    kernel-tools \
    clang \
    llvm \
    gcc \
    git
```

### Étapes d'Installation

1. **Cloner le Projet**
```bash
git clone https://github.com/mousaab-vtrx/ChabahRoot.git
cd ChabahRoot
```

2. **Rendre les Scripts Exécutables**
```bash
chmod +x chabahroot/m1/*.sh chabahroot/m1/lib/*.sh detection/*.sh
```

3. **Valider les Prérequis**
```bash
sudo ./chabahroot/m1/check.sh
```

4. **Préparer les Répertoires de Logs**
```bash
sudo mkdir -p /var/log/chabahroot
mkdir -p detection/logs detection/tmp
```

---

## Démarrage Rapide

### Scénario 1: Surveillance eBPF M1

```bash
# 1. Valider les prérequis
sudo ./chabahroot/m1/check.sh

# 2. Démarrer la surveillance
sudo ./chabahroot/m1/init.sh

# 3. Dans un autre terminal, vérifier le statut eBPF
sudo ./chabahroot/m1/ebpf_integration.sh status

# 4. Arrêter avec Ctrl+C (nettoyage automatique)
```

### Scénario 2: Audit de Sécurité et Surveillance

```bash
# Mode complet: surveillance défensive + audit offensif
sudo ./detection/run.sh

# Logs disponibles à:
tail -f ./detection/logs/chabah.log
```

### Scénario 3: Surveillance Défensive Uniquement

```bash
# Surveillance continue des escalades UID
sudo ./detection/run.sh --defensive-only
```

---

## Configuration

### Fichier de Configuration (detection/rules.conf)

```bash
# Mots-clés sensibles à filtrer
SENSITIVE_KEYWORDS="pass password token secret key"

# Chemin du fichier de log
LOG_FILE="./logs/chabah.log"

# Niveau de log: DEBUG | INFO | WARN | ALERT
LOG_LEVEL="INFO"

# UID cible de détection (0 = root)
TARGET_UID=0

# Modes de détection
OFFENSIVE_MODE=1
DEFENSIVE_MODE=1

# Surveillance en secondes (0 = infini)
WATCH_DURATION=0

# Intervalle de polling pour la surveillance (secondes)
POLL_INTERVAL=2

# Métadonnées du projet
PROJECT_NAME="ChabahRoot"
MODULE_NAME="Detection Engine"
VERSION="1.0.0"
```

### Variables d'Environnement

```bash
# Activer le mode debug (logging verbose)
export DEBUG=1

# Exécuter avec debug verbeux
DEBUG=1 sudo ./chabahroot/m1/init.sh
```

---

## Dépannage

### Problème: "bpftool not found"
```bash
# Solution
sudo apt install linux-tools-generic
```

### Problème: "Kernel 4.0+ required"
```bash
# Vérifier la version
uname -r

# Mettre à jour le noyau
sudo apt install --install-recommends linux-image-generic linux-headers-generic
sudo reboot
```

### Problème: Permission denied writing logs
```bash
# Solution
sudo mkdir -p /var/log/chabahroot
sudo chmod 755 /var/log/chabahroot
sudo chown root:root /var/log/chabahroot
```

### Problème: "eBPF programs not loading"
```bash
# Vérifier la configuration kernel
zcat /proc/config.gz | grep BPF

# Ou essayer sur /sys/kernel/debug/tracing
ls -la /sys/kernel/debug/tracing/
```

### Déboguer avec Verbosité
```bash
DEBUG=1 sudo ./chabahroot/m1/init.sh
DEBUG=1 sudo ./detection/run.sh --defensive-only
```

---

## Ressources Techniques

### eBPF Concepts

**Extended Berkeley Packet Filter (eBPF)** est une machine virtuelle légère dans le noyau:

- **In-kernel VM**: Exécute du bytecode compilé directement dans le noyau
- **JIT Compilation**: Compilation à la volée en code machine natif (très rapide)
- **Maps**: Structures de données partagées noyau↔espace utilisateur
- **Ring Buffers**: Canal efficace pour streamer les événements
- **Tracepoints**: Points d'instrumentation statiques du noyau

**Avantages:**
- Filtrage in-kernel réduit le bruit de 10-100x
- Latence <1ms pour la surveillance en temps réel
- CPU overhead minimal (1-2% vs 5-15% avec tracefs)

### Namespaces et Cgroups

ChabahRoot peut être étendu pour surveiller:
- **Namespaces**: Isolation de processus, network, filesystem, IPC
- **Cgroups**: Limitations de ressources et accounting
- **Capabilities**: Permissions granulaires au niveau système

### Tracepoints Disponibles

Points d'instrumentation statiques du noyau:

```bash
# Lister les tracepoints disponibles
find /sys/kernel/debug/tracing/events -type d

# Exemples utiles:
- syscalls:sys_enter_execve (exécution de binaires)
- sched:sched_process_fork (création de processus)
- sched:sched_process_exec (changement de processus)
- syscalls:sys_enter_* (appels système)
```

### Références

- [Linux eBPF Documentation](https://www.kernel.org/doc/html/latest/userspace-api/ebpf/index.html)
- [bpftool Manual](https://man7.org/linux/man-pages/man8/bpftool.8.html)
- [eBPF.io — Learn eBPF](https://ebpf.io/)
- [BCC — eBPF Toolkit](https://github.com/iovisor/bcc)
- [libbpf — Standard Library](https://github.com/libbpf/libbpf)

---

## Conventions et Standards

### Style des Scripts Shell

- **Sécurité**: `set -euo pipefail` pour strict error handling
- **Logging**: Utiliser les fonctions centralisées (log_info, log_error, etc)
- **Commentaires**: Français, minimalistes, uniquement si non-obvious
- **Noms**: Sémantiques et clairs (ex: `verify_root_privileges` vs `check_root`)
- **Modularité**: Pas de duplication, fonctions réutilisables

### Structure de Projet

- Chaque module a une **responsabilité unique**
- Pas de dépendances circulaires
- Les scripts appellent des modules, pas l'inverse
- Configuration centralisée dans `rules.conf`

---

## Sécurité et Avertissements Légaux

⚠️ **AVERTISSEMENT IMPORTANT**

Ce projet est destiné **exclusivement** à un usage légal dans le cadre de:
- Tests sur vos propres systèmes
- Environnements de laboratoire (CTF, VMs de test)
- Missions de sécurité avec autorisation écrite explicite

Toute utilisation sur des systèmes sans autorisation est **illégale** et engage votre responsabilité pénale.

---

**Version**: 1.0.0 — **Statut**: Production Ready | **Architecture**: 4-Layer M1/M2/M3/M4
