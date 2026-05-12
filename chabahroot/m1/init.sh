#!/usr/bin/env bash
# ChabahRoot M1 — Initialisation de la surveillance du noyau
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

LOG_STORAGE_PATH="/var/log/chabahroot"
EBPF_PROGRAM_PATH="./ebpf_integration.sh"
EBPF_ENABLED=0

# Vérifier la disponibilité des outils eBPF
check_ebpf_availability() {
    log_debug "Vérification des outils eBPF (bpftool, clang)..."
    
    require_command bpftool "bpftool" || return 1
    require_command clang "clang" || return 1
    
    [[ -f "$EBPF_PROGRAM_PATH" ]] || {
        log_error "Script d'intégration eBPF non trouvé: $EBPF_PROGRAM_PATH"
        return 1
    }
    
    log_success "Outils eBPF détectés"
}

# Initialiser le traçage eBPF
initialize_ebpf() {
    log_info "Initialisation du traçage eBPF..."
    
    if ! check_ebpf_availability; then
        log_error "Impossible d'initialiser eBPF - outils manquants"
        return 1
    fi
    
    if bash "$EBPF_PROGRAM_PATH" load; then
        EBPF_ENABLED=1
        log_success "Programmes eBPF chargés avec succès"
        return 0
    else
        log_error "Échec du chargement des programmes eBPF"
        return 1
    fi
}

# Valider les prérequis système
validate_system_requirements() {
    log_info "Vérification des prérequis système..."
    
    verify_root_privileges || exit 1
    
    mkdir -p "$LOG_STORAGE_PATH"
    
    local kernel_version=$(uname -r | cut -d. -f1)
    [[ $kernel_version -ge 4 ]] || {
        log_error "Noyau 4.0+ requis pour eBPF (trouvé: $(uname -r))"
        exit 1
    }
    
    log_success "Système prêt — Noyau $(uname -r)"
}

# Gestionnaire d'arrêt
shutdown_tracing() {
    log_info "Arrêt du traçage eBPF..."
    
    if [[ "$EBPF_ENABLED" == "1" ]]; then
        if bash "$EBPF_PROGRAM_PATH" cleanup; then
            log_success "Nettoyage eBPF complété"
        else
            log_error "Erreur lors du nettoyage eBPF"
        fi
    fi
    
    log_success "Arrêt complété"
}

setup_signal_handlers "shutdown_tracing"

main() {
    echo "ChabahRoot M1 — SURVEILLANCE DU NOYAU (eBPF)"
    echo
    
    validate_system_requirements
    initialize_ebpf
    
    echo
    log_info "Traçage eBPF actif — Appuyez sur Ctrl+C pour arrêter"
    log_info "Résultats disponibles via bpftool map"
    
    # Maintenir le traçage actif
    while true; do
        sleep 1
    done
}

main "$@"
