#!/usr/bin/env bash
# ChabahRoot - Orchestrateur Service de Kernel Ingestion (M1)
# Auteur: MOUSAAB EL HARMALI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/lib_utils".sh"

readonly EBPF_INTEGRATION="$SCRIPT_DIR/integration.sh"
readonly M1_PIDFILE="/tmp/chabah_m1.pid"

verify_m1_prerequisites() {
    log_info "Verification des prerequis M1"

    verify_root_privileges || return 1
    require_command bpftool "bpftool" || return 1
    require_command clang "clang" || return 1
    require_command llvm-strip "llvm-strip" || return 1

    if [[ ! -d /sys/kernel/debug/tracing/events/syscalls ]]; then
        log_error "Acces aux tracepoints indisponible"
        log_info "Conseil: sudo mount -t debugfs none /sys/kernel/debug"
        return 1
    fi

    log_success "Tous les prerequis M1 sont valides"
}

load_ebpf_programs() {
    log_info "Chargement des programmes eBPF M1"

    if bash "$EBPF_INTEGRATION" load; then
        log_success "Programmes eBPF charges avec succes"
        return 0
    fi

    log_error "Echec du chargement des programmes eBPF"
    return 1
}

cleanup_m1() {
    log_info "Nettoyage de la couche M1"
    rm -f "$M1_PIDFILE"
    bash "$EBPF_INTEGRATION" cleanup || true
    log_success "Couche M1 nettoyee"
}

shutdown_handler() {
    log_info "Signal d'arret recu"
    cleanup_m1
    exit 0
}

run_foreground() {
    trap shutdown_handler INT TERM EXIT
    echo "$$" > "$M1_PIDFILE"
    log_success "M1 demarre et pret (PID=$$)"

    while true; do
        sleep 1
    done
}

show_status() {
    if [[ -f "$M1_PIDFILE" ]]; then
        local pid
        pid="$(cat "$M1_PIDFILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_success "M1 actif (PID=$pid)"
        else
            log_error "Fichier PID present mais processus absent"
        fi
    else
        log_info "M1 non demarre"
    fi

    bash "$EBPF_INTEGRATION" status || true
}

main() {
    case "${1:-start}" in
        start)
            log_separator "Initialisation M1 - Couche ingestion eBPF"
            verify_m1_prerequisites || exit 1
            load_ebpf_programs || exit 1
            run_foreground
            ;;
        stop)
            log_info "Arret de M1"
            cleanup_m1
            ;;
        status)
            show_status
            ;;
        *)
            log_info "Usage: $0 {start|stop|status}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
