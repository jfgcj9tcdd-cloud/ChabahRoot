#!/usr/bin/env bash
# Cette sonde echoue tot avant toute ecriture dans tracefs.
# Le reste de la plateforme suppose que les tracepoints syscall existent
# deja et que root peut les activer sans ambiguite a cet endroit.
# Si ce contrat casse, les etages suivants ne produisent que du bruit.
# Auteur M1 : Mousaab EL HARMALI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly TRACEFS_PATH="/sys/kernel/tracing"
readonly REQUIRED_TRACEPOINTS=(
    "syscalls/sys_enter_execve"
    "syscalls/sys_enter_setuid"
    "syscalls/sys_enter_setgid"
    "syscalls/sys_enter_prctl"
)

check_tracepoint() {
    local tracepoint="$1"

    [[ -e "$TRACEFS_PATH/events/$tracepoint/enable" ]]
}

main() {
    local tracepoint

    log_info "Verifying M1 prerequisites"
    verify_root_privileges || exit 1

    if [[ ! -d "$TRACEFS_PATH" ]]; then
        log_error "tracefs is not mounted at $TRACEFS_PATH"
        exit 1
    fi

    for tracepoint in "${REQUIRED_TRACEPOINTS[@]}"; do
        if ! check_tracepoint "$tracepoint"; then
            log_error "Missing tracepoint: $tracepoint"
            exit 1
        fi
    done

    log_success "M1 prerequisites are valid"
}

main "$@"
