#!/usr/bin/env bash
# Orchestrateur Service de Kernel Ingestion (M1)
# MOUSAAB EL HARMALI
# Architecture: tracefs pour capture kernel (elimine dependance eBPF)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly TRACER="$SCRIPT_DIR/tracer.sh"
readonly M1_PIDFILE="/tmp/chabah_m1.pid"
readonly M1_TRACER_PID="/tmp/chabah_m1_tracer.pid"

verify_m1_prerequisites() {
    log_info "Verification des prerequis M1"

    verify_root_privileges || return 1
    
    # Check tracefs availability
    if [[ ! -d /sys/kernel/tracing ]]; then
        log_error "tracefs non disponible - impossible de proceeder"
        return 1
    fi
    
    log_success "Tous les prerequis M1 sont valides"
}

start_tracer() {
    log_info "Demarrage du traceur kernel (tracefs)"

    # Enable tracepoints
    bash "$TRACER" enable || return 1
    
    # Start streaming in background
    bash "$TRACER" stream > /tmp/chabah_kernel_events.pipe 2>&1 &
    local tracer_pid=$!
    
    echo "$tracer_pid" > "$M1_TRACER_PID"
    log_success "Traceur demarre (PID=$tracer_pid)"
}

cleanup_m1() {
    log_info "Nettoyage de la couche M1"
    
    # Stop tracer
    if [[ -f "$M1_TRACER_PID" ]]; then
        local tracer_pid
        tracer_pid=$(cat "$M1_TRACER_PID" 2>/dev/null || true)
        if [[ -n "$tracer_pid" ]]; then
            kill "$tracer_pid" 2>/dev/null || true
        fi
        rm -f "$M1_TRACER_PID"
    fi
    
    # Disable tracepoints
    bash "$TRACER" disable 2>/dev/null || true
    
    rm -f "$M1_PIDFILE"
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
    
    log_success "M1 demarre - Capture kernel via tracefs (PID=$$)"

    while true; do
        sleep 1
    done
}

show_status() {
    if [[ -f "$M1_PIDFILE" ]]; then
        local pid
        pid="$(cat "$M1_PIDFILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_success "M1 actif (PID=$pid, Mode=tracefs)"
        else
            log_error "Fichier PID present mais processus absent"
        fi
    else
        log_info "M1 non demarre"
    fi
    
    if [[ -f "$M1_TRACER_PID" ]]; then
        local tracer_pid
        tracer_pid=$(cat "$M1_TRACER_PID" 2>/dev/null || true)
        if [[ -n "$tracer_pid" ]] && kill -0 "$tracer_pid" 2>/dev/null; then
            log_success "Traceur actif (PID=$tracer_pid)"
        fi
    fi
}

main() {
    case "${1:-start}" in
        start)
            log_separator "Initialisation M1 - Capture kernel via tracefs"
            verify_m1_prerequisites || exit 1
            start_tracer || exit 1
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
