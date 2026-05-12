#!/usr/bin/env bash
# ChabahRoot M1 — Validation des prérequis système
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

# Vérification de la version du noyau (4.0+ pour eBPF)
validate_kernel_version() {
    log_info "Vérification de la version du noyau..."
    local kernel_version
    kernel_version=$(uname -r | cut -d. -f1)
    
    if [[ $kernel_version -lt 4 ]]; then
        log_error "Noyau 4.0+ requis pour eBPF (détecté: $(uname -r))"
        return 1
    fi
    log_success "Noyau eBPF-compatible: $(uname -r)"
}

# Vérification des outils eBPF disponibles
verify_ebpf_tools() {
    log_info "Vérification des outils eBPF..."
    local missing=()
    
    for tool in bpftool clang llvm-strip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Outils manquants: ${missing[*]}"
        log_info "Installation Debian/Ubuntu: apt install linux-tools-generic clang llvm"
        return 1
    fi
    log_success "Tous les outils eBPF disponibles"
}

# Préparation du répertoire de stockage des logs
prepare_log_directory() {
    log_info "Préparation du répertoire de logs..."
    local log_path="/var/log/chabahroot"
    
    if ! mkdir -p "$log_path" 2>/dev/null; then
        log_error "Impossible de créer: $log_path"
        return 1
    fi
    log_success "Répertoire de logs prêt: $log_path"
}

# Affichage du statut système
show_system_info() {
    echo
    echo "ChabahRoot M1 — Statut Système"
    echo "========================================"
    echo "Noyau: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPUs: $(nproc)"
    echo "Mémoire: $(free -h | awk '/^Mem:/{print $2}')"
    echo
    echo "Outils eBPF:"
    command -v bpftool >/dev/null 2>&1 && echo "  ✓ bpftool" || echo "  ✗ bpftool absent"
    command -v clang >/dev/null 2>&1 && echo "  ✓ clang" || echo "  ✗ clang absent"
    command -v llvm-strip >/dev/null 2>&1 && echo "  ✓ llvm-strip" || echo "  ✗ llvm-strip absent"
    echo
}

main() {
    echo "ChabahRoot M1 — Vérification des Prérequis"
    echo
    
    validate_kernel_version || exit 1
    verify_ebpf_tools || exit 1
    prepare_log_directory || exit 1
    
    show_system_info
    log_success "Tous les prérequis satisfaits"
}

main "$@"
