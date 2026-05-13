#!/usr/bin/env bash
# ChabahRoot M1 - Kernel Event Tracer via tracefs
# MOUSAAB EL HARMALI
# No eBPF compilation required - uses kernel tracefs directly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly TRACEFS_PATH="/sys/kernel/tracing"
readonly EVENTS_FILE="$TRACEFS_PATH/trace_pipe"
readonly ENABLED_EVENTS_FILE="/tmp/chabah_enabled_events"

# Enable specific syscall tracepoints
enable_tracepoints() {
    log_info "Activation des tracepoints: execve, setuid, setgid, prctl"
    
    # Clear previous state
    echo 0 > "$TRACEFS_PATH/tracing_on" 2>/dev/null || {
        log_error "Impossible d'acceder a tracefs - verifier privileges root"
        return 1
    }
    
    echo "" > "$TRACEFS_PATH/trace" 2>/dev/null || true
    
    # Enable specific syscall tracepoints
    local tracepoints=(
        "syscalls:sys_enter_execve"
        "syscalls:sys_enter_setuid"
        "syscalls:sys_enter_setgid"
        "syscalls:sys_enter_prctl"
    )
    
    for tp in "${tracepoints[@]}"; do
        echo 1 > "$TRACEFS_PATH/events/$tp/enable" 2>/dev/null || {
            log_warn "Impossible d'activer $tp"
            continue
        }
    done
    
    # Set output format
    echo "noirq nosched-switch" > "$TRACEFS_PATH/trace_options" 2>/dev/null || true
    echo 1 > "$TRACEFS_PATH/tracing_on" || {
        log_error "Impossible de demarrer tracing"
        return 1
    }
    
    log_success "Tracepoints actives avec succes"
    echo "${tracepoints[@]}" > "$ENABLED_EVENTS_FILE"
}

# Parse tracefs output and normalize to M3 format
parse_trace_event() {
    local line="$1"
    local timestamp pid comm event_type
    
    # Format: <exec>-1234 [001] 123456789.123456: sys_enter_execve: ...
    if [[ $line =~ ([^-]+)-([0-9]+).*([0-9]{10}\.[0-9]{6}):\ sys_enter_([a-z_]+) ]]; then
        comm="${BASH_REMATCH[1]}"
        pid="${BASH_REMATCH[2]}"
        timestamp="${BASH_REMATCH[3]}"
        local syscall="${BASH_REMATCH[4]}"
        
        case "$syscall" in
            execve) event_type=1 ;;
            setuid) event_type=2 ;;
            setgid) event_type=3 ;;
            prctl) event_type=4 ;;
            *) event_type=0 ;;
        esac
        
        # Extract argv from trace output
        local argv=""
        if [[ $line =~ filename=([^\s]+) ]]; then
            argv="${BASH_REMATCH[1]}"
        fi
        
        # Get process context
        local uid
        uid=$(awk -v p="$pid" '$1 == p {print $2; exit}' /proc/net/stat 2>/dev/null || echo "0")
        
        # Output in compatible format
        echo "pid=$pid ppid=1 uid=$uid gid=0 ts=$(date +%s%N) comm=$comm argv=$argv event_type=$event_type"
    fi
}

# Stream events from tracefs
stream_events() {
    log_info "Streaming evenements depuis tracefs"
    
    if [[ ! -f "$EVENTS_FILE" ]]; then
        log_error "Tracefs non disponible: $EVENTS_FILE"
        return 1
    fi
    
    # Follow trace_pipe in real-time
    tail -f "$EVENTS_FILE" | while IFS= read -r line; do
        # Filter only syscall events
        if [[ $line =~ sys_enter_(execve|setuid|setgid|prctl) ]]; then
            parse_trace_event "$line"
        fi
    done
}

disable_tracepoints() {
    log_info "Desactivation des tracepoints"
    
    if [[ -f "$ENABLED_EVENTS_FILE" ]]; then
        mapfile -t tracepoints < "$ENABLED_EVENTS_FILE"
        for tp in "${tracepoints[@]}"; do
            echo 0 > "$TRACEFS_PATH/events/$tp/enable" 2>/dev/null || true
        done
    fi
    
    echo 0 > "$TRACEFS_PATH/tracing_on" 2>/dev/null || true
    rm -f "$ENABLED_EVENTS_FILE"
    
    log_success "Tracepoints desactives"
}

main() {
    local action="${1:-stream}"
    
    case "$action" in
        enable)
            enable_tracepoints
            ;;
        stream)
            stream_events
            ;;
        disable)
            disable_tracepoints
            ;;
        *)
            log_error "Usage: $0 {enable|stream|disable}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
