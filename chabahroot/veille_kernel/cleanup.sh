#!/usr/bin/env bash
# Ce raccourci offre un point d arret explicite aux operateurs
# Il delegue a la couche d integration tracefs pour conserver le meme
# ordre de desactivation, qu un arret vienne d une commande manuelle ou du processus long qui porte la capture en avant plan
# Mousaab EL HARMALI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_info "Stopping M1 tracefs capture"
bash "$SCRIPT_DIR/integration.sh" cleanup
log_success "M1 cleanup complete"
