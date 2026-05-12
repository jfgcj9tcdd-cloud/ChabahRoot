#!/usr/bin/env bash
# Bibliothèque d'utilitaires ChabahRoot
set -euo pipefail

# Enregistrement avec horodatage
log_info() {
    printf "[INFO] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Enregistrement des erreurs
log_error() {
    printf "[ERROR] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

# Enregistrement de succès
log_success() {
    printf "[OK] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Enregistrement de débogage
log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] && \
        printf "[DEBUG] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Séparateur visuel pour les logs
log_separator() {
    local title="${1:-}"
    local line="=========================================================="
    if [[ -n "$title" ]]; then
        echo "$line [ $title ]"
    else
        echo "$line"
    fi
}

# Vérification des privilèges root
verify_root_privileges() {
    [[ "$(id -u)" -eq 0 ]] && return 0
    log_error "Privilèges root requis - utilisation: sudo $0"
    return 1
}

# Gestion des signaux d'interruption
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

# Vérification de la disponibilité des commandes
require_command() {
    local cmd="$1" desc="${2:-$cmd}"
    command -v "$cmd" >/dev/null 2>&1 || {
        log_error "Commande requise non trouvée: $desc"
        return 1
    }
}
