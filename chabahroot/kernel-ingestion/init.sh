#!/usr/bin/env bash
# Initialisation couche M1
# MOUSAAB EL HARMALI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_separator "Initialisation M1 - Couche ingestion eBPF"
bash "$SCRIPT_DIR/check.sh" || exit 1
bash "$SCRIPT_DIR/integration.sh" load
log_success "Couche M1 initialisee"
