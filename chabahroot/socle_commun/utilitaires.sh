#!/usr/bin/env bash
# Le reste de la plateforme partage ce fichier pour les besoins communs.
# Il reste volontairement sobre, sans couleur ni sortie cachee sur stdout,
# car le pipeline melange journaux humains, substitutions de commande,
# et flux de donnees brutes dans une meme session shell.
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/chabah.log}"
AUDIT_LOG="${AUDIT_LOG:-$LOG_DIR/audit.log}"

resolve_log_paths() {
    if [[ "$LOG_DIR" != /* ]]; then
        LOG_DIR="$PROJECT_ROOT/$LOG_DIR"
    fi

    if [[ "$LOG_FILE" != /* ]]; then
        LOG_FILE="$PROJECT_ROOT/$LOG_FILE"
    fi

    if [[ "$AUDIT_LOG" != /* ]]; then
        AUDIT_LOG="$PROJECT_ROOT/$AUDIT_LOG"
    fi
}

init_log_storage() {
    resolve_log_paths

    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        LOG_DIR="/tmp/chabahroot"
        LOG_FILE="$LOG_DIR/chabah.log"
        AUDIT_LOG="$LOG_DIR/audit.log"
        mkdir -p "$LOG_DIR"
    fi

    if [[ -e "$LOG_FILE" && ! -w "$LOG_FILE" ]] || [[ ! -e "$LOG_FILE" && ! -w "$LOG_DIR" ]]; then
        LOG_DIR="/tmp/chabahroot"
        LOG_FILE="$LOG_DIR/chabah.log"
        AUDIT_LOG="$LOG_DIR/audit.log"
        mkdir -p "$LOG_DIR"
    fi

    touch "$LOG_FILE" "$AUDIT_LOG" 2>/dev/null || true
}

log_message() {
    local level="$1"
    local category="$2"
    local message="$3"
    local timestamp entry

    init_log_storage
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    entry="[$timestamp] [$level] [$category] $message"
    printf '%s\n' "$entry" >> "$LOG_FILE" 2>/dev/null || true
    printf '%s\n' "$entry" >&2
}

log_alert() { log_message "ALERT" "$1" "$2"; }
log_error() { log_message "ERROR" "$1" "$2"; }
log_info() { log_message "INFO" "$1" "$2"; }
log_warn() { log_message "WARN" "$1" "$2"; }

log_debug() {
    [[ "${DEBUG_MODE:-0}" == "1" ]] || return 0
    log_message "DEBUG" "$1" "$2"
}

log_success() {
    log_message "SUCCESS" "$1" "$2"
}

log_separator() {
    local title="${1:-section}"
    local entry="[SECTION] $title"

    init_log_storage
    printf '%s\n' "$entry" >> "$LOG_FILE" 2>/dev/null || true
    printf '%s\n' "$entry" >&2
}

record_audit() {
    local action="$1"
    local detail="$2"
    local timestamp

    init_log_storage
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] [UID:%s] ACTION=%s DETAILS=%s\n' \
        "$timestamp" "$(id -u)" "$action" "$detail" >> "$AUDIT_LOG" 2>/dev/null || true
}

verify_root() {
    [[ "$EUID" -eq 0 ]] && return 0
    log_error "SYSTEM" "This action requires root"
    record_audit "ROOT_CHECK_FAILED" "euid=$EUID"
    return 1
}

verify_command() {
    local cmd="$1"

    command -v "$cmd" >/dev/null 2>&1 || {
        log_warn "SYSTEM" "Missing command: $cmd"
        return 1
    }
}

verify_file() {
    local path="$1"
    local mode="${2:-r}"

    case "$mode" in
        r) [[ -r "$path" ]] ;;
        w) [[ -w "$path" ]] ;;
        x) [[ -x "$path" ]] ;;
        *) return 1 ;;
    esac || {
        log_warn "SYSTEM" "File check failed for $path mode=$mode"
        return 1
    }
}

cleanup_pidfile() {
    local pid_file="$1"
    local pid=""

    if [[ -f "$pid_file" ]]; then
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
        rm -f "$pid_file"
    fi
}

validate_json() {
    local payload="$1"

    command -v jq >/dev/null 2>&1 || {
        log_warn "SYSTEM" "jq is required for JSON validation"
        return 1
    }

    jq empty >/dev/null 2>&1 <<< "$payload" || {
        log_warn "SYSTEM" "Invalid JSON payload"
        return 1
    }
}

filter_sensitive() {
    local text="$1"
    local keyword

    for keyword in ${SENSITIVE_KEYWORDS:-}; do
        [[ -n "$keyword" ]] || continue
        if grep -qi "$keyword" <<< "$text"; then
            log_alert "FILTER" "Sensitive keyword '$keyword' seen in log path"
            return 0
        fi
    done

    return 1
}

init_log() {
    init_log_storage
    printf '[BOOT] %s %s %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$(hostname)" "$(whoami)" >> "$LOG_FILE" 2>/dev/null || true
}

export -f log_alert log_error log_info log_warn log_debug log_success \
    log_separator record_audit verify_root verify_command verify_file \
    cleanup_pidfile validate_json filter_sensitive init_log

init_log_storage
