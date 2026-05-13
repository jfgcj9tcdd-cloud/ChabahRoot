#!/usr/bin/env bash
# Ce script est le seul endroit qui touche directement a tracefs.
# La surface d evenement reste volontairement petite parce que le parseur
# suivant depend de noms syscall stables et de chemins filesystem reels.
# La notation ancienne avec deux points ne doit plus reapparaitre ici.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly TRACEFS_PATH="/sys/kernel/tracing"
readonly EVENTS_FILE="$TRACEFS_PATH/trace_pipe"
readonly ENABLED_EVENTS_FILE="/tmp/chabah_enabled_events"
readonly TRACEPOINTS=(
    "syscalls/sys_enter_execve"
    "syscalls/sys_enter_setuid"
    "syscalls/sys_enter_setgid"
    "syscalls/sys_enter_prctl"
)

read_status_value() {
    local pid="$1"
    local key="$2"

    awk -v target="$key" '$1 == target ":" { print $2; exit }' "/proc/$pid/status" 2>/dev/null || true
}

enable_tracepoints() {
    local tracepoint

    log_info "Enabling tracepoints for execve, setuid, setgid, and prctl"

    echo 0 > "$TRACEFS_PATH/tracing_on" 2>/dev/null || {
        log_error "Cannot write to tracefs; check root access"
        return 1
    }

    : > "$TRACEFS_PATH/trace" 2>/dev/null || true

    for tracepoint in "${TRACEPOINTS[@]}"; do
        echo 1 > "$TRACEFS_PATH/events/$tracepoint/enable" 2>/dev/null || {
            log_warn "Could not enable $tracepoint"
            continue
        }
    done

    printf '%s\n' "${TRACEPOINTS[@]}" > "$ENABLED_EVENTS_FILE"
    echo 1 > "$TRACEFS_PATH/tracing_on"
    log_success "Tracepoints enabled"
}

parse_trace_event() {
    local line="$1"
    local comm pid syscall argv uid gid ppid

    if [[ ! "$line" =~ ^[[:space:]]*([^[:space:]-]+)-([0-9]+).*[[:space:]]sys_enter_([a-z_]+): ]]; then
        return 1
    fi

    comm="${BASH_REMATCH[1]}"
    pid="${BASH_REMATCH[2]}"
    syscall="${BASH_REMATCH[3]}"
    argv=""

    case "$syscall" in
        execve)
            [[ "$line" =~ filename=\"?([^\",[:space:]]+) ]] && argv="${BASH_REMATCH[1]}"
            event_type=1
            ;;
        setuid)
            [[ "$line" =~ uid=([0-9]+) ]] && argv="setuid(${BASH_REMATCH[1]})"
            event_type=2
            ;;
        setgid)
            [[ "$line" =~ gid=([0-9]+) ]] && argv="setgid(${BASH_REMATCH[1]})"
            event_type=3
            ;;
        prctl)
            [[ "$line" =~ option=([0-9]+) ]] && argv="prctl(option=${BASH_REMATCH[1]})"
            event_type=4
            ;;
        *)
            return 1
            ;;
    esac

    uid="$(read_status_value "$pid" "Uid")"
    gid="$(read_status_value "$pid" "Gid")"
    ppid="$(read_status_value "$pid" "PPid")"

    uid="${uid:-0}"
    gid="${gid:-0}"
    ppid="${ppid:-1}"

    printf 'pid=%s ppid=%s uid=%s gid=%s ts=%s comm=%s argv=%s event_type=%s\n' \
        "$pid" "$ppid" "$uid" "$gid" "$(date +%s%N)" "$comm" "$argv" "$event_type"
}

stream_events() {
    local line

    log_info "Streaming events from tracefs"

    [[ -r "$EVENTS_FILE" ]] || {
        log_error "trace_pipe is not readable: $EVENTS_FILE"
        return 1
    }

    while IFS= read -r line; do
        [[ "$line" =~ sys_enter_(execve|setuid|setgid|prctl) ]] || continue
        parse_trace_event "$line" || true
    done < "$EVENTS_FILE"
}

disable_tracepoints() {
    local tracepoint

    log_info "Disabling tracepoints"

    if [[ -f "$ENABLED_EVENTS_FILE" ]]; then
        while IFS= read -r tracepoint; do
            [[ -n "$tracepoint" ]] || continue
            echo 0 > "$TRACEFS_PATH/events/$tracepoint/enable" 2>/dev/null || true
        done < "$ENABLED_EVENTS_FILE"
    fi

    echo 0 > "$TRACEFS_PATH/tracing_on" 2>/dev/null || true
    rm -f "$ENABLED_EVENTS_FILE"
    log_success "Tracepoints disabled"
}

show_status() {
    local tracepoint enabled

    if [[ ! -d "$TRACEFS_PATH/events" ]]; then
        log_warn "tracefs events directory is not available"
        return 0
    fi

    for tracepoint in "${TRACEPOINTS[@]}"; do
        enabled="$(cat "$TRACEFS_PATH/events/$tracepoint/enable" 2>/dev/null || echo "0")"
        log_info "$tracepoint enabled=$enabled"
    done
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
        status)
            show_status
            ;;
        *)
            log_error "Usage: $0 {enable|stream|disable|status}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
