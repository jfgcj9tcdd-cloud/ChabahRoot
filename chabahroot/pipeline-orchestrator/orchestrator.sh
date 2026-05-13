#!/usr/bin/env bash
# Compatibilite historique - orchestrateur M4 delegue vers services/m4_integration
# Auteur: Equipe Cyber
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

exec bash "$PROJECT_ROOT/services/m4_integration/complete_pipeline.sh" "$@"
