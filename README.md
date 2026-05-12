# ChabahRoot — Module Analyste Cyber

> **Moteur logique et modes** — Système de surveillance et d'audit de sécurité Linux modulaire en Bash pur.

---

## Table des matières

1. [Présentation](#présentation)
2. [Architecture](#architecture)
3. [Fonctionnalités](#fonctionnalités)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Utilisation](#utilisation)
7. [Format des logs](#format-des-logs)
8. [Tests](#tests)
9. [Sécurité et avertissements légaux](#sécurité-et-avertissements-légaux)

---

## Présentation

**ChabahRoot** est un moteur de surveillance et d'analyse de sécurité Linux entièrement écrit en Bash. Il est composé de modules indépendants qui travaillent ensemble pour :

- Détecter les **transitions UID vers UID 0** (escalade root)
- Générer des **alertes structurées et horodatées**
- **Filtrer les mots-clés sensibles** dans les processus et commandes
- Auditer la configuration système à la recherche de **vecteurs d'escalade**
- Journaliser tous les événements dans `/dev/shm/chabah.log`

---

## Architecture

```
ChabahRoot/
├── run.sh          # Orchestrateur principal — point d'entrée
├── defensive.sh    # Module défensif — surveillance continue
├── offensive.sh    # Module offensif — audit one-shot
├── logger.sh       # Module de journalisation centralisée
├── rules.conf      # Configuration des règles et paramètres
└── README.md       # Documentation du projet
```

### Flux d'exécution

```
run.sh
  ├── Charge rules.conf
  ├── Charge logger.sh
  ├── Lance defensive.sh (boucle en arrière-plan)
  │     ├── detect_uid_escalation()   → scan ps, détection root
  │     ├── scan_env_variables()      → filtre variables sensibles
  │     └── scan_cmdlines()           → filtre commandes root
  └── Lance offensive.sh (one-shot)
        ├── audit_suid_binaries()     → binaires SUID suspects
        ├── audit_world_writable()    → fichiers accessibles en écriture
        ├── check_sudoers()           → règles sudo dangereuses
        ├── check_cron_jobs()         → tâches planifiées suspectes
        ├── check_login_history()     → historique connexions root
        └── generate_ioc_report()    → rapport IOC final
```

---

## Fonctionnalités

### Module Défensif (`defensive.sh`)
| Fonction | Description |
|---|---|
| `detect_uid_escalation` | Scanne tous les processus et détecte les UID=0 nouveaux |
| `check_suspicious_process` | Identifie les outils d'escalade connus (sudo, nc, bash...) |
| `scan_env_variables` | Filtre les variables d'environnement pour des secrets |
| `scan_cmdlines` | Analyse les arguments des processus root via `/proc` |
| `purge_seen_pids` | Nettoie les PIDs terminés pour éviter les faux positifs |

### Module Offensif (`offensive.sh`)
| Fonction | Description |
|---|---|
| `audit_suid_binaries` | Détecte les binaires SUID non standards |
| `audit_world_writable` | Trouve les fichiers critiques accessibles en écriture |
| `check_sudoers` | Analyse `/etc/sudoers` pour `NOPASSWD` et `ALL=(ALL)` |
| `check_cron_jobs` | Inspecte les crontabs pour des commandes suspectes |
| `check_login_history` | Analyse l'historique de connexion root via `last` |
| `generate_ioc_report` | Génère un rapport de synthèse des indicateurs de compromission |

### Module Logger (`logger.sh`)
| Fonction | Description |
|---|---|
| `init_log` | Initialise le fichier de log avec en-tête de session |
| `log_message` | Écrit un message formaté (niveau, catégorie, UID, timestamp) |
| `filter_sensitive` | Détecte les mots-clés sensibles dans une chaîne |
| `log_separator` | Séparateurs visuels dans les logs |

---

## Installation

```bash
# 1. Cloner ou copier le projet
git clone <repo> ChabahRoot
cd ChabahRoot

# 2. Rendre les scripts exécutables
chmod +x run.sh defensive.sh offensive.sh logger.sh

# 3. Vérifier que /dev/shm est disponible (tmpfs en RAM)
ls /dev/shm/
```

**Dépendances requises** (disponibles par défaut sur Linux) :
- `bash` ≥ 4.0
- `ps`, `grep`, `awk`, `find`, `last`

---

## Configuration

Modifier `rules.conf` pour adapter le comportement :

```bash
# Mots-clés sensibles à détecter
SENSITIVE_KEYWORDS="pass password token secret key"

# Fichier de log (tmpfs recommandé pour la performance)
LOG_FILE="/dev/shm/chabah.log"

# Niveau de log : DEBUG | INFO | WARN | ALERT
LOG_LEVEL="INFO"

# Intervalle de scan défensif (en secondes)
POLL_INTERVAL=2

# Activer/désactiver les modules
OFFENSIVE_MODE=1
DEFENSIVE_MODE=1
```

---

## Utilisation

```bash
# Mode complet (défensif continu + audit offensif one-shot)
sudo ./run.sh

# Surveillance défensive uniquement (boucle continue)
sudo ./run.sh --defensive-only

# Audit offensif uniquement (one-shot et quitte)
sudo ./run.sh --offensive-only

# Défensif sans audit offensif
sudo ./run.sh --no-offensive

# Afficher l'aide
./run.sh --help
```

### Consulter les logs en temps réel

```bash
# Suivre le log en direct
tail -f /dev/shm/chabah.log

# Filtrer uniquement les alertes critiques
grep "\[ALERT\]" /dev/shm/chabah.log

# Filtrer par module
grep "\[DEFENSIVE\]" /dev/shm/chabah.log
grep "\[OFFENSIVE\]" /dev/shm/chabah.log

# Compter les alertes
grep -c "\[ALERT\]" /dev/shm/chabah.log
```

---

## Format des logs

Chaque entrée de log suit ce format structuré :

```
[TIMESTAMP] [NIVEAU] [CATEGORIE] [UID=X] MESSAGE
```

**Exemples réels :**

```
============================================================
  ChabahRoot - Analyste Cyber v1.0.0
  Session démarrée : 2024-01-15 14:30:22
  PID principal    : 12345
  Hôte             : serveur-prod
  Utilisateur      : user (UID=1000)
============================================================
[2024-01-15 14:30:22] [INFO]  [SYSTEM]    [UID=1000] Démarrage de ChabahRoot — Mode : full
[2024-01-15 14:30:23] [ALERT] [DEFENSIVE] [UID=1000] Transition ROOT détectée ! PID=999 | PPID=998 | CMD=sudo
[2024-01-15 14:30:23] [ALERT] [DEFENSIVE] [UID=1000] Processus suspect root identifié : 'sudo' (PID=999)
[2024-01-15 14:30:25] [ALERT] [FILTER]    [UID=1000] Mot-clé sensible détecté : 'password' dans : --password=secret123
[2024-01-15 14:30:26] [ALERT] [OFFENSIVE] [UID=0]    Binaire SUID non standard détecté : /usr/local/bin/myscript
[2024-01-15 14:30:26] [WARN]  [OFFENSIVE] [UID=0]    Règle ALL=(ALL) détectée dans sudoers : admin ALL=(ALL) ALL
```

**Niveaux de log :**
| Niveau | Couleur | Usage |
|---|---|---|
| `DEBUG` | Cyan | Informations de débogage |
| `INFO` | Bleu | Événements normaux |
| `WARN` | Jaune | Avertissements non critiques |
| `ALERT` | Rouge | Événements critiques à investiguer |

---

## Tests

### Test 1 — Vérification du démarrage

```bash
sudo ./run.sh --offensive-only
echo "Code retour : $?"
ls -la /dev/shm/chabah.log
```

### Test 2 — Simulation de filtre de mots-clés sensibles

```bash
# Lance le moteur défensif
sudo ./run.sh --defensive-only &
MOTOR_PID=$!

# Simule un processus avec un argument sensible (dans une autre console)
sleep 60 --password=monPassword123 &

# Vérifie les alertes
sleep 3
grep "ALERT.*password" /dev/shm/chabah.log

kill $MOTOR_PID
```

### Test 3 — Détection d'un binaire SUID

```bash
# Crée un binaire SUID de test dans /tmp (sans danger)
sudo cp /bin/sleep /tmp/test_suid_chabah
sudo chmod u+s /tmp/test_suid_chabah

# Lance l'audit offensif
sudo ./run.sh --offensive-only

# Vérifie la détection
grep "test_suid_chabah" /dev/shm/chabah.log

# Nettoie
sudo rm /tmp/test_suid_chabah
```

### Test 4 — Vérification du format de log

```bash
sudo ./run.sh --offensive-only
# Vérifie la structure des entrées
grep -E "^\[20[0-9]{2}-" /dev/shm/chabah.log | head -5
```

### Test 5 — Interruption propre

```bash
sudo ./run.sh --defensive-only &
PID=$!
sleep 5
kill -INT $PID
wait $PID
echo "Arrêt propre OK"
grep "SESSION TERMINÉE" /dev/shm/chabah.log
```

---

## Sécurité et avertissements légaux

> ⚠️ **AVERTISSEMENT IMPORTANT**
>
> Ce projet est destiné **exclusivement** à un usage légal dans le cadre de :
> - Tests sur vos propres systèmes
> - Environnements de laboratoire (CTF, VMs de test)
> - Missions de sécurité avec autorisation écrite explicite
>
> Toute utilisation sur des systèmes sans autorisation est **illégale** et engage votre responsabilité pénale.

**Considérations de sécurité du projet lui-même :**
- Les logs sont écrits dans `/dev/shm` (tmpfs RAM) — ils disparaissent au redémarrage
- Aucune donnée n'est envoyée sur le réseau
- Le moteur ne modifie aucun fichier système
- Recommandé de tourner avec un utilisateur dédié (pas directement en root)

---

## Auteur

Module développé dans le cadre du projet **ChabahRoot**
Composant : Analyste Cyber — Moteur logique et modes
Version : 1.0.0
