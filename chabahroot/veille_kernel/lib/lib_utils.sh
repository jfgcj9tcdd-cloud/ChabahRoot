#!/usr/bin/env bash
# These helpers stay small on purpose because M1 runs before the richer
# shared layer is necessarily available. They write logs to stderr only,
# which keeps command substitution safe in the scripts that need to emit
# machine readable values on stdout.
set -euo pipefail

log_info() {
    printf "[INFO] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_warn() {
    printf "[WARN] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_error() {
    printf "[ERROR] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_success() {
    printf "[OK] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] || return 0
    printf "[DEBUG] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

log_separator() {
    local title="${1:-section}"
    printf "[SECTION] %s\n" "$title" >&2
}

verify_root_privileges() {
    [[ "$(id -u)" -eq 0 ]] && return 0
    log_error "Root privileges are required: sudo $0"
    return 1
}

require_command() {
    local cmd="$1"
    local desc="${2:-$cmd}"

    command -v "$cmd" >/dev/null 2>&1 || {
        log_error "Required command not found: $desc"
        return 1
    }
}
