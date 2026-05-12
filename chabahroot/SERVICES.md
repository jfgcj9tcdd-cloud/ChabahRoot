# ChabahRoot — Architecture des Services

**Version**: 1.0.0 | **Date**: May 12, 2026

## Vue d'ensemble

ChabahRoot est organisé selon une architecture modulaire en **4 services** indépendants et interconnectés.

```
chabahroot/
├── kernel-ingestion/          (M1 - Service d'Ingestion Kernel)
├── rules-engine/              (M2 - Moteur de Règles)
├── event-normalizer/          (M3 - Normaliseur d'Événements)
├── pipeline-orchestrator/     (M4 - Orchestrateur du Pipeline)
└── shared/                    (Ressources partagées)
```

---

## Service M1: Kernel Ingestion

**Responsable**: MOUSAAB EL HARMALI

### Description
Service d'ingestion des événements système via eBPF. Capture les événements au niveau kernel avec une surcharge minimale (<1-2% CPU).

### Fichiers principaux
- `orchestrator.sh` — Orchestrateur du service M1
- `integration.sh` — Intégration eBPF et compilation
- `check.sh` — Vérification des prérequis
- `init.sh` — Initialisation de la surveillance
- `cleanup.sh` — Nettoyage des ressources
- `ebpf/event_capture.c` — Programmes kernel eBPF
- `lib/lib_utils.sh` — Utilitaires partagés

### Événements capturés
- Exécution de binaires (`sys_enter_execve`)
- Changements UID (`sys_enter_setuid`)
- Changements GID (`sys_enter_setgid`)
- Modifications de capacités (`sys_enter_prctl`)

### Utilisation
```bash
sudo ./kernel-ingestion/orchestrator.sh start
sudo ./kernel-ingestion/orchestrator.sh stop
sudo ./kernel-ingestion/check.sh
```

---

## Service M2: Rules Engine

**Responsable**: Équipe Cyber

### Description
Moteur d'analyse et de détection basé sur des règles JSON. Évalue les événements contre 7 règles de détection de menaces.

### Fichiers principaux
- `rules_engine.sh` — Moteur de règles principal
- `detection_rules.json` — Définitions des 7 règles
- `offensive_audit.sh` — Audit de sécurité offensif
- `defensive_monitor.sh` — Surveillance défensive en continu

### Règles de détection
1. `rule_exec_001` — Exécution depuis emplacements dangereux
2. `rule_priv_001` — Escalade de privilèges via setuid
3. `rule_priv_002` — Processus non autorisés en root
4. `rule_susp_001` — Motifs de commandes suspects
5. `rule_caps_001` — Abus de capacités
6. `rule_cred_001` — Données sensibles dans les arguments
7. `rule_suid_001` — Audit binaires SUID

### Utilisation
```bash
./rules-engine/rules_engine.sh
./rules-engine/offensive_audit.sh
./rules-engine/defensive_monitor.sh
```

---

## Service M3: Event Normalizer

**Responsable**: Équipe Cyber

### Description
Normalise et enrichit les événements bruts du kernel en JSON structuré. Filtre les données sensibles et enrichit avec le contexte processus parent.

### Fichiers principaux
- `ringbuf_reader.sh` — Lecteur du ring buffer eBPF

### Fonctionnalités
- ✓ Lecture continue du ring buffer
- ✓ Décodage hex → JSON structuré
- ✓ Enrichissement contexte parent (`/proc/`)
- ✓ Filtrage données sensibles (password, token, secret, key)
- ✓ Mise en cache et traitement batch

### Schéma d'événement JSON
```json
{
  "timestamp": "2026-05-12T20:04:00Z",
  "timestamp_ns": 1715538240000000000,
  "event_type": "exec",
  "process": {
    "pid": 12345,
    "ppid": 1,
    "comm": "bash",
    "cmdline": "/bin/bash /tmp/script.sh"
  },
  "credentials": {
    "uid": 1000,
    "gid": 1000
  },
  "data": {
    "argv": "/bin/bash /tmp/script.sh"
  }
}
```

### Utilisation
```bash
./event-normalizer/ringbuf_reader.sh
```

---

## Service M4: Pipeline Orchestrator

**Responsable**: Équipe Cyber

### Description
Orchestrateur principal qui coordonne les 4 services. Gère le cycle de vie, la communication inter-services via FIFO, et les tests.

### Fichiers principaux
- `orchestrator.sh` — Orchestrateur principal du pipeline
- `integration_tests.sh` — Suite de tests d'intégration
- `run_detection.sh` — Lancement détection

### Modes d'opération
- `run` — Démarrage interactif
- `start` — Démarrage en arrière-plan
- `stop` — Arrêt du pipeline
- `status` — État des services
- `test` — Exécution des tests

### Flux de données
```
M1 (Kernel) → Ring Buffer → M3 (Normalizer)
   → FIFO Pipe → M2 (Rules Engine) → Alertes/Logs
```

### Utilisation
```bash
sudo ./pipeline-orchestrator/orchestrator.sh run
sudo ./pipeline-orchestrator/orchestrator.sh status
sudo ./pipeline-orchestrator/orchestrator.sh test
```

---

## Ressources partagées

**Localisation**: `shared/`

### Fichiers
- `logger.sh` — Logging structuré avec couleurs ANSI
- `rules.conf` — Configuration centralisée
- `logs/` — Répertoire des logs
- `tmp/` — Fichiers temporaires et état

### Configuration
Éditer `shared/rules.conf` pour modifier:
- Niveaux de log (`LOG_LEVEL`)
- Fichiers de sortie (`LOG_FILE`)
- Mots-clés sensibles (`SENSITIVE_KEYWORDS`)

---

## Flux de communication

```
┌─────────────────────────────────────────────────────┐
│   M1: Kernel Ingestion (MOUSAAB EL HARMALI)        │
│   • Probes eBPF sur syscalls                        │
│   • Ring Buffer streaming (256KB)                   │
│   • <1ms latency, 1-2% CPU overhead               │
└────────────────┬────────────────────────────────────┘
                 │ Ring Buffer
                 ↓
┌─────────────────────────────────────────────────────┐
│   M3: Event Normalizer (Équipe Cyber)              │
│   • Décodage événements                             │
│   • Normalisation JSON                              │
│   • Enrichissement contexte                         │
│   • Filtrage données sensibles                      │
└────────────────┬────────────────────────────────────┘
                 │ FIFO Pipe (event_stream.pipe)
                 ↓
┌─────────────────────────────────────────────────────┐
│   M2: Rules Engine (Équipe Cyber)                   │
│   • Évaluation règles (jq conditions)              │
│   • Génération alertes                              │
│   • Actions (journal, slack, email)                 │
└────────────────┬────────────────────────────────────┘
                 │ Alertes & Logs
                 ↓
┌─────────────────────────────────────────────────────┐
│   M4: Pipeline Orchestrator (Équipe Cyber)         │
│   • Gestion du cycle de vie                        │
│   • Monitoring & auto-restart                       │
│   • Tests d'intégration                            │
└─────────────────────────────────────────────────────┘
```

---

## Démarrage rapide

### 1. Vérifier les prérequis
```bash
sudo ./chabahroot/kernel-ingestion/check.sh
```

### 2. Pipeline complet
```bash
sudo ./chabahroot/pipeline-orchestrator/orchestrator.sh run
```

### 3. Consulter les alertes
```bash
tail -f ./chabahroot/shared/logs/chabah.log
tail -f /tmp/chabah_pipeline_state/alerts.log
```

### 4. Vérifier le statut
```bash
sudo ./chabahroot/pipeline-orchestrator/orchestrator.sh status
```

---

## Structure des répertoires

```
chabahroot/
├── kernel-ingestion/          M1 - Ingestion eBPF
│   ├── orchestrator.sh
│   ├── integration.sh
│   ├── check.sh
│   ├── init.sh
│   ├── cleanup.sh
│   ├── ebpf/
│   │   └── event_capture.c
│   └── lib/
│       └── lib_utils.sh
├── rules-engine/              M2 - Moteur de Règles
│   ├── rules_engine.sh
│   ├── detection_rules.json
│   ├── offensive_audit.sh
│   └── defensive_monitor.sh
├── event-normalizer/          M3 - Normaliseur d'Événements
│   └── ringbuf_reader.sh
├── pipeline-orchestrator/     M4 - Orchestrateur Principal
│   ├── orchestrator.sh
│   ├── integration_tests.sh
│   └── run_detection.sh
├── shared/                    Ressources partagées
│   ├── logger.sh
│   ├── rules.conf
│   ├── logs/
│   └── tmp/
└── SERVICES.md                Cette documentation
```

---

## Auteurs

- **M1 (Kernel Ingestion)**: MOUSAAB EL HARMALI
- **M2 (Rules Engine)**: Équipe Cyber
- **M3 (Event Normalizer)**: Équipe Cyber
- **M4 (Pipeline Orchestrator)**: Équipe Cyber

---

## Spécifications techniques

- **Kernel minimum**: Linux 4.0+
- **Architecture**: x86_64
- **Config kernel requise**: `CONFIG_BPF=y`, `CONFIG_BPF_SYSCALL=y`
- **Outils**: `bpftool`, `clang`, `llvm-strip`, `jq`
- **Langage**: Bash 4.0+, C (eBPF), JSON
- **License**: GPL v2

---

**Version**: 1.0.0 | **Dernière mise à jour**: 2026-05-12
