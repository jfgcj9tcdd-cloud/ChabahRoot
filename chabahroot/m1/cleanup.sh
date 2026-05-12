#!/usr/bin/env bash
# ChabahRoot M1 — Nettoyage des ressources eBPF
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

EBPF_PROGRAM_PATH="./ebpf_integration.sh"

# Nettoyer les programmes eBPF chargés
cleanup_ebpf() {
    log_info "Nettoyage des programmes eBPF..."
    
    [[ -f "$EBPF_PROGRAM_PATH" ]] || {
        log_error "Script d'intégration eBPF non trouvé"
        return 1
    }
    
    if bash "$EBPF_PROGRAM_PATH" cleanup; then
        log_success "Programmes eBPF nettoyés"
        return 0
    else
        log_error "Erreur lors du nettoyage eBPF"
        return 1
    fi
}

# Vérifier les permissions d'accès requis
verify_access_permissions() {
    verify_root_privileges || exit 1
}

main() {
    echo "ChabahRoot M1 — NETTOYAGE eBPF"
    echo
    
    verify_access_permissions
    cleanup_ebpf
    
    echo
    log_success "Nettoyage eBPF complété"
}

main "$@"
