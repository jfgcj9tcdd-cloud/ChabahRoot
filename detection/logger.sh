#!/usr/bin/env bash
# ChabahRoot — Module de journalisation
# Gestion centralisée des logs structurés avec couleurs ANSI
set -euo pipefail

# Charger la configuration si non déjà chargée
[[ -z "${LOG_FILE:-}" ]] && {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/rules.conf" 2>/dev/null || {
        echo "[FATAL] Unable to load rules.conf" >&2
        return 1
    }
}

# ANSI color codes
readonly COLOR_INFO="\033[0;34m"
readonly COLOR_WARN="\033[0;33m"
readonly COLOR_ALERT="\033[0;31m"
readonly COLOR_DEBUG="\033[0;36m"
readonly COLOR_SUCCESS="\033[0;32m"
readonly COLOR_RESET="\033[0m"

# Initialize log file with header
init_log() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    mkdir -p "$log_dir" || return 1
    
    {
        echo "=========== ${PROJECT_NAME} ${MODULE_NAME} v${VERSION} ==========="
        printf "Started: %s | Host: %s | User: %s (UID=%d)\n" \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$(hostname)" "$(whoami)" "$(id -u)"
        echo "=============================================================="
    } >> "$LOG_FILE" 2>/dev/null
}

# Core logging function
# Args: $1=level, $2=category, $3=message
log_message() {
    local level="$1" category="$2" message="$3"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Filter by log level
    case "$LOG_LEVEL" in
        DEBUG) ;;
        INFO)  [[ "$level" == "DEBUG" ]] && return 0 ;;
        WARN)  [[ "$level" =~ (DEBUG|INFO) ]] && return 0 ;;
        ALERT) [[ "$level" != "ALERT" ]] && return 0 ;;
    esac
    
    local entry="[$ts] [$level] [$category] $message"
    echo "$entry" >> "$LOG_FILE" 2>/dev/null
    
    # Console output with colors
    local color="$COLOR_INFO"
    [[ "$level" == "WARN" ]] && color="$COLOR_WARN"
    [[ "$level" == "ALERT" ]] && color="$COLOR_ALERT"
    [[ "$level" == "DEBUG" ]] && color="$COLOR_DEBUG"
    
    echo -e "${color}${entry}${COLOR_RESET}"
}

# Convenience wrappers
log_alert() { log_message "ALERT" "$1" "$2"; }
log_info() { log_message "INFO" "$1" "$2"; }
log_warn() { log_message "WARN" "$1" "$2"; }
log_debug() { log_message "DEBUG" "$1" "$2"; }

# Detect sensitive keywords in text
filter_sensitive() {
    local text="$1" found=1
    
    for keyword in $SENSITIVE_KEYWORDS; do
        if echo "$text" | grep -qi "$keyword"; then
            local excerpt
            excerpt=$(echo "$text" | cut -c1-80)
            log_alert "FILTER" "Sensitive keyword '$keyword': $excerpt"
            found=0
        fi
    done
    
    return $found
}

# Log separator for visual breaks
log_separator() {
    local title="${1:-}"
    local line="=========================================================="
    
    if [[ -n "$title" ]]; then
        echo "$line [ $title ]" >> "$LOG_FILE" 2>/dev/null
        echo -e "${COLOR_SUCCESS}$line [ $title ]${COLOR_RESET}"
    else
        echo "$line" >> "$LOG_FILE" 2>/dev/null
        echo -e "${COLOR_SUCCESS}${line}${COLOR_RESET}"
    fi
}
