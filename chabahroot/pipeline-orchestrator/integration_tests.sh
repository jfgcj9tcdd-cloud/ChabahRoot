#!/usr/bin/env bash
# Compatibilite historique - tests M4 delegues vers services/m4_integration
# Auteur: Équipe Cyber
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

exec bash "$PROJECT_ROOT/services/m4_integration/m4_integration_tests.sh" "$@"
