#!/usr/bin/env bash
#Mousaab El harmali
#check.sh: Validation des prerequis systeme

set -euo pipefail

# Charger les bibliotheques d'utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

# VALIDATION DE LA VERSION DU NOYAU
validate_kernel_version() {
    # verifier si que le noyau supporte eBPF >4.0
    log_info "Verification de la version du noyau: en cours"

    local kernel_version=$(uname -r | cut -d. -f1)
    
    if [[ $kernel_version -lt 4 ]]; then
        log_error "Noyau 4.0+ requis pour eBPF (detecte: $(uname -r))"
        return 1
    fi

    log_success "Noyau eBPF-compatible detecte: $(uname -r)"
    return 0
}

# VALIDATION DES CAPACITeS SYSTeME
confirm_system_capabilities() {
    # Verifier les outils et capacites systeme requis
    log_info "Verification des outils systeme: en cours"

    local missing_tools=()

    # Verifier bpftool
    if ! command -v bpftool >/dev/null 2>&1; then
        missing_tools+=("bpftool")
    fi

    # Verifier clang
    if ! command -v clang >/dev/null 2>&1; then
        missing_tools+=("clang")
    fi

    # Verifier llvm
    if ! command -v llvm-strip >/dev/null 2>&1; then
        missing_tools+=("llvm-strip")
    fi

    # Verifier privileges root
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Privileges root requis"
        return 1
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Outils manquants: ${missing_tools[*]}"
        log_info "Installation sur Debian/Ubuntu: apt install linux-tools-generic clang llvm"
        return 1
    fi

    log_success "Tous les outils eBPF sont disponibles"
    return 0
}

# PRePARATION DU RePERTOIRE DE LOG
prepare_log_directory() {
    # Preparer le repertoire de stockage des logs
    local log_path="/var/log/chabahroot"
    
    log_info "Preparation du repertoire de logs: en cours"

    if ! mkdir -p "$log_path" 2>/dev/null; then
        log_error "Impossible de creer le repertoire: $log_path"
        return 1
    fi

    log_success "Repertoire de logs prêt: $log_path"
    return 0
}

# AFFICHAGE DES STATUTS SYSTeME
display_system_status() {
    # Afficher un resume des capacites systeme
    echo
    echo "╔════════════════════════════════════════════╗"
    echo "║    ChabahRoot M1 — Statut Systeme          ║"
    echo "╚════════════════════════════════════════════╝"
    echo
    echo "Noyau: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPUs: $(nproc)"
    echo "Memoire: $(free -h | grep Mem | awk '{print $2}')"
    echo
    echo "Outils eBPF:"
    command -v bpftool >/dev/null 2>&1 && echo "  ✓ bpftool: $(bpftool version | head -1)" || echo "  ✗ bpftool: manquant"
    command -v clang >/dev/null 2>&1 && echo "  ✓ clang: $(clang --version | head -1)" || echo "  ✗ clang: manquant"
    command -v llvm-strip >/dev/null 2>&1 && echo "  ✓ llvm-strip: detecte" || echo "  ✗ llvm-strip: manquant"
    echo
}

# EXECUTION PRINCIPALE
main() {
    # Fonction pour la validation
    echo "CHABAHROOT M1 - VeRIFICATION DES PReREQUIS"
    echo

    # Effectuer les verifications
    validate_kernel_version || { log_error "Arrêt"; exit 1; }
    confirm_system_capabilities || { log_error "Arrêt"; exit 1; }
    prepare_log_directory || { log_error "Arrêt"; exit 1; }

    # Afficher le statut complet
    display_system_status
    
    log_success "Tous les prerequis sont satisfaits"
}

main "$@"
