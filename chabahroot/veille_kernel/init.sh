#!/usr/bin/env bash
# Ce lanceur garde un chemin de depart tres court pour les essais.
# La couche d ingestion a une seule responsabilite ici : valider tracefs
# puis activer les tracepoints qui alimentent le reste du pipeline.
# Toute logique annexe doit rester hors de ce point d entree.
# Auteur M1 : Mousaab EL HARMALI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_separator "Starting M1 tracefs ingestion"
bash "$SCRIPT_DIR/check.sh"
bash "$SCRIPT_DIR/integration.sh" load
log_success "M1 ingestion initialized"
