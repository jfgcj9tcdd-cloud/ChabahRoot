#!/usr/bin/env bash
# Bibliotheque d'utilitaires ChabahRoot
#MOUSAAB EL HARMALI
set -euo pipefail

# Enregistrement avec horodatage
log_info() {
    printf "[INFO] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Enregistrement des erreurs
log_error() {
    printf "[ERROR] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

# Enregistrement de succes
log_success() {
    printf "[OK] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Enregistrement de debogage
log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] && \
        printf "[DEBUG] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Separateur visuel pour les logs
log_separator() {
    local title="${1:-}"
    local line="=========================================================="
    if [[ -n "$title" ]]; then
        echo "$line [ $title ]"
    else
        echo "$line"
    fi
}

# Verification des privileges root
verify_root_privileges() {
    [[ "$(id -u)" -eq 0 ]] && return 0
    log_error "Privileges root requis - utilisation: sudo $0"
    return 1
}

setup_signal_handlers() {
    local cleanup_fn="$1"
    trap "$cleanup_fn" INT TERM EXIT
}

# Validation des variables d'environnement critiques
validate_environment() {
    local var
    for var in "$@"; do
        [[ -n "${!var:-}" ]] && continue
        log_error "Variable d'environnement manquante: $var"
        return 1
    done
    return 0
}

# Verification de la disponibilite des commandes
require_command() {
    local cmd="$1" desc="${2:-$cmd}"
    command -v "$cmd" >/dev/null 2>&1 || {
        log_error "Commande requise non trouvee: $desc"
        return 1
    }
}
