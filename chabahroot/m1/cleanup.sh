#!/usr/bin/env bash
# Mousaab El harmali
# cleanup.sh  Nettoyage des ressources eBPF

set -euo pipefail

# Charger les bibliotheques d'utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

# CONFIGURATION
EBPF_PROGRAM_PATH="./ebpf_integration.sh"

# NETTOYAGE EBPF
cleanup_ebpf() {
    # Nettoyer les programmes eBPF charges
    log_info "Nettoyage des programmes eBPF..."

    if [[ ! -f "$EBPF_PROGRAM_PATH" ]]; then
        log_error "Script d'integration eBPF non trouve"
        return 1
    fi

    if bash "$EBPF_PROGRAM_PATH" cleanup; then
        log_success "Programmes eBPF nettoyes"
        return 0
    else
        log_error "Erreur lors du nettoyage eBPF"
        return 1
    fi
}


# VERIFICATION DES PERMISSIONS
verify_access_permissions() {
    # Verifier les privileges d'acces requis
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Privileges root requis pour le nettoyage"
        exit 1
    fi

    log_debug "Privileges root verifies"
}


# EXECUTION PRINCIPALE

main() {
    # Fonction principale pour le nettoyage
    echo "CHABAHROOT M1 - NETTOYAGE EBPF"
    echo

    verify_access_permissions
    cleanup_ebpf

    echo
    log_success "Nettoyage eBPF complete"
}

main "$@"
