#!/usr/bin/env bash
# Ce point d entree reste en place pour la compatibilite operatoire.
# Les usages existants appellent encore orchestrator.sh par habitude,
# mais la logique maintenue vit maintenant dans run_detection.sh.
# Ce saut evite deux flux de controle qui divergeraient avec le temps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$SCRIPT_DIR/run_detection.sh" "$@"
