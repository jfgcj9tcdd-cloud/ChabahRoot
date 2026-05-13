#!/usr/bin/env bash
# ChabahRoot - Module de journalisation
# Auteur: Equipe ChabahRoot
# Gere les logs structures avec une sortie console lisible
set -euo pipefail

if [[ -z "${LOG_FILE:-}" ]]; then
    LOGGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../shared/rules.conf"" 2>/dev/null || {
        echo "[FATAL] Impossible de charger rules.conf" >&2
        return 1
    }
fi

readonly COLOR_INFO="\033[0;34m"
readonly COLOR_WARN="\033[0;33m"
readonly COLOR_ALERT="\033[0;31m"
readonly COLOR_DEBUG="\033[0;36m"
readonly COLOR_SUCCESS="\033[0;32m"
readonly COLOR_RESET="\033[0m"

resolve_log_file() {
    local script_dir project_root preferred_dir fallback_dir

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    project_root="$(cd "$script_dir/../.." && pwd)"
    preferred_dir="$(dirname "$LOG_FILE")"
    fallback_dir="$project_root/logs"

    mkdir -p "$preferred_dir" 2>/dev/null || true

    if [[ -e "$LOG_FILE" && -w "$LOG_FILE" ]]; then
        return 0
    fi

    if [[ ! -e "$LOG_FILE" && -w "$preferred_dir" ]]; then
        return 0
    fi

    mkdir -p "$fallback_dir" 2>/dev/null || true

    if [[ -w "$fallback_dir" ]]; then
        LOG_FILE="$fallback_dir/chabah.log"
        return 0
    fi

    LOG_FILE="/tmp/chabah.log"
}

init_log() {
    local log_dir

    resolve_log_file
    log_dir="$(dirname "$LOG_FILE")"
    mkdir -p "$log_dir" 2>/dev/null || true

    {
        echo "=========== ${PROJECT_NAME} ${MODULE_NAME} v${VERSION} ==========="
        printf "Demarre: %s | Hote: %s | Utilisateur: %s (UID=%d)\n" \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$(hostname)" "$(whoami)" "$(id -u)"
        echo "=============================================================="
    } >> "$LOG_FILE" 2>/dev/null || true
}

log_message() {
    local level="$1" category="$2" message="$3"
    local ts color entry

    resolve_log_file
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    case "${LOG_LEVEL:-INFO}" in
        DEBUG) ;;
        INFO) [[ "$level" == "DEBUG" ]] && return 0 ;;
        WARN) [[ "$level" =~ (DEBUG|INFO) ]] && return 0 ;;
        ALERT) [[ "$level" != "ALERT" ]] && return 0 ;;
    esac

    entry="[$ts] [$level] [$category] $message"
    printf '%s\n' "$entry" >> "$LOG_FILE" 2>/dev/null || true

    color="$COLOR_INFO"
    [[ "$level" == "WARN" ]] && color="$COLOR_WARN"
    [[ "$level" == "ALERT" ]] && color="$COLOR_ALERT"
    [[ "$level" == "DEBUG" ]] && color="$COLOR_DEBUG"

    printf '%b%s%b\n' "$color" "$entry" "$COLOR_RESET"
}

log_alert() { log_message "ALERT" "$1" "$2"; }
log_error() { log_message "ALERT" "$1" "$2"; }
log_info() { log_message "INFO" "$1" "$2"; }
log_warn() { log_message "WARN" "$1" "$2"; }
log_debug() { log_message "DEBUG" "$1" "$2"; }

log_success() {
    local category="$1" message="$2" ts entry

    resolve_log_file
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    entry="[$ts] [SUCCESS] [$category] $message"
    printf '%s\n' "$entry" >> "$LOG_FILE" 2>/dev/null || true
    printf '%b%s%b\n' "$COLOR_SUCCESS" "$entry" "$COLOR_RESET"
}

filter_sensitive() {
    local text="$1" found=1 excerpt keyword

    for keyword in ${SENSITIVE_KEYWORDS:-}; do
        if grep -qi "$keyword" <<< "$text"; then
            excerpt="$(echo "$text" | cut -c1-80)"
            log_alert "FILTER" "Mot cle sensible '$keyword': $excerpt"
            found=0
        fi
    done

    return "$found"
}

log_separator() {
    local title="${1:-}"
    local line="=========================================================="

    resolve_log_file

    if [[ -n "$title" ]]; then
        printf '%s [ %s ]\n' "$line" "$title" >> "$LOG_FILE" 2>/dev/null || true
        printf '%b%s [ %s ]%b\n' "$COLOR_SUCCESS" "$line" "$title" "$COLOR_RESET"
    else
        printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
        printf '%b%s%b\n' "$COLOR_SUCCESS" "$line" "$COLOR_RESET"
    fi
}

resolve_log_file
