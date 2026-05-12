#!/usr/bin/env bash
# Compatibilite historique - audit offensif delegue vers services/m2_detection
# Auteur: Équipe ChabahRoot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/services/m2_detection/offensive_audit.sh"
else
    exec bash "$PROJECT_ROOT/services/m2_detection/offensive_audit.sh" "$@"
fi
