#!/usr/bin/env bash
# This process owns the lifetime of the tracefs capture stage.
# It leaves raw events in a fifo like stream file so the rest of the
# pipeline can attach without gaining write access to tracefs, which is
# the boundary that matters here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly TRACER="$SCRIPT_DIR/tracer.sh"
readonly M1_PIDFILE="/tmp/chabah_m1.pid"
readonly M1_TRACER_PID="/tmp/chabah_m1_tracer.pid"
readonly M1_EVENT_STREAM="/tmp/chabah_kernel_events.pipe"

verify_m1_prerequisites() {
    log_info "Verifying M1 prerequisites"
    bash "$SCRIPT_DIR/check.sh"
}

start_tracer() {
    log_info "Starting tracefs tracer"
    bash "$TRACER" enable
    : > "$M1_EVENT_STREAM"
    bash "$TRACER" stream >> "$M1_EVENT_STREAM" 2>>"$M1_EVENT_STREAM" &
    echo "$!" > "$M1_TRACER_PID"
    log_success "Tracer started with PID=$!"
}

cleanup_m1() {
    log_info "Stopping M1"

    if [[ -f "$M1_TRACER_PID" ]]; then
        local tracer_pid
        tracer_pid="$(cat "$M1_TRACER_PID" 2>/dev/null || true)"
        [[ -n "$tracer_pid" ]] && kill "$tracer_pid" 2>/dev/null || true
        rm -f "$M1_TRACER_PID"
    fi

    bash "$TRACER" disable 2>/dev/null || true
    rm -f "$M1_PIDFILE"
    log_success "M1 stopped"
}

shutdown_handler() {
    log_warn "Shutdown signal received"
    cleanup_m1
    exit 0
}

run_foreground() {
    trap shutdown_handler INT TERM
    trap cleanup_m1 EXIT
    echo "$$" > "$M1_PIDFILE"
    log_success "M1 is active with PID=$$"

    while true; do
        sleep 1
    done
}

show_status() {
    if [[ -f "$M1_PIDFILE" ]]; then
        local pid
        pid="$(cat "$M1_PIDFILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_success "M1 active with PID=$pid"
        else
            log_warn "PID file exists but process is gone"
        fi
    else
        log_info "M1 is not running"
    fi

    bash "$TRACER" status
}

main() {
    case "${1:-start}" in
        start)
            verify_m1_prerequisites
            start_tracer
            run_foreground
            ;;
        stop)
            cleanup_m1
            ;;
        status)
            show_status
            ;;
        *)
            log_error "Usage: $0 {start|stop|status}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
