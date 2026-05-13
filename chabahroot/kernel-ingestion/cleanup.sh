#!/usr/bin/env bash
# Service nettoyage M1
# MOUSAAB EL HARMALI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_info "Nettoyage de la couche M1"
bash "$SCRIPT_DIR/integration.sh" cleanup
log_success "Couche M1 nettoyee"
