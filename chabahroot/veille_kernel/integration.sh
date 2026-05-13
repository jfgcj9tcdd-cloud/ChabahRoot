#!/usr/bin/env bash
# Ce script sert de passage unique pour la couche d ingestion.
# Les autres points d entree le sollicitent afin que l activation des
# tracepoints passe par une seule implementation, surtout quand un arret
# doit defaire un demarrage partiel sans hypothese fragile sur l etat.
# Auteur M1 : Mousaab EL HARMALI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly TRACER="$SCRIPT_DIR/tracer.sh"

main() {
    local action="${1:-status}"

    case "$action" in
        load)
            bash "$TRACER" enable
            ;;
        cleanup)
            bash "$TRACER" disable
            ;;
        status)
            bash "$TRACER" status
            ;;
        *)
            log_error "Usage: $0 {load|cleanup|status}"
            exit 1
            ;;
    esac
}

main "$@"
