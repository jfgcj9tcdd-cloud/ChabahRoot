#!/usr/bin/env bash
# This script is the narrow waist of the ingestion layer.
# Other entry points call it so that tracepoints are toggled through one
# implementation only, which matters when cleanup must unwind partial
# startup without guessing what already happened.
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
