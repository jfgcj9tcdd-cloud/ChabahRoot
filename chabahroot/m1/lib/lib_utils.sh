#!/usr/bin/env bash
# Bibliothèque d'utilitaires ChabahRoot
# Auteur: Mousaab El harmali
# Description: Fonctions communes et utilitaires pour tous les scripts ChabahRoot

set -euo pipefail

# Enregistrement avec horodatage
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Enregistrement des erreurs
log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Enregistrement de succès
log_success() {
    echo "[OK] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Enregistrement de débogage (verbeux)
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Vérification des privilèges root
verify_root_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Privilèges root requis"
        log_error "Utilisation: sudo $0"
        return 1
    fi
    return 0
}

# Gestion des signaux d'interruption
setup_signal_handlers() {
    local cleanup_function="$1"
    trap "$cleanup_function" INT TERM EXIT
    log_debug "Gestionnaires de signaux configurés"
}

# Validation des variables d'environnement critiques
validate_environment() {
    local required_vars=("$@")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Variable d'environnement manquante: $var"
            return 1
        fi
    done
    return 0
}

# Vérification de la disponibilité des commandes
require_command() {
    local cmd="$1"
    local description="${2:-$cmd}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Commande requise non trouvée: $description"
        return 1
    fi
    log_debug "Commande trouvée: $description"
    return 0
}
