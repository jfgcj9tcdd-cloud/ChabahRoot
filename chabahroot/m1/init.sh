#!/usr/bin/env bash
# Auteur: Mousaab El harmali
# ChabahRoot — init.sh — Couche d'ingestion du noyau
# Membre 1 (M1) — Ingénieur noyau

set -euo pipefail

# Charger les bibliothèques d'utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

###############################################
# CONFIGURATION
###############################################
# Configuration de base pour le traçage eBPF
LOG_STORAGE_PATH="/var/log/chabahroot"
OUTPUT_PIPE="/tmp/chabahroot_pipe"   # Tuyau nommé vers M3

# Paramètres d'intégration eBPF
EBPF_ENABLED=0
EBPF_PROGRAM_PATH="./ebpf_integration.sh"

###############################################
# INTÉGRATION EBPF
###############################################
check_ebpf_availability() {
    # Vérifier si les outils eBPF sont disponibles
    log_debug "Vérification des outils eBPF (bpftool, clang)..."
    
    if ! command -v bpftool >/dev/null 2>&1; then
        log_error "bpftool non trouvé - installer: apt install linux-tools-generic"
        return 1
    fi
    
    if ! command -v clang >/dev/null 2>&1; then
        log_error "clang non trouvé - installer: apt install clang llvm"
        return 1
    fi

    if [[ ! -f "$EBPF_PROGRAM_PATH" ]]; then
        log_error "Script d'intégration eBPF non trouvé: $EBPF_PROGRAM_PATH"
        return 1
    fi

    log_success "Outils eBPF détectés"
    return 0
}

initialize_ebpf() {
    # Initialiser le traçage eBPF
    log_info "Initialisation du traçage eBPF..."

    if ! check_ebpf_availability; then
        log_error "Impossible d'initialiser eBPF - outils requis manquants"
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

###############################################
# VALIDATION DES PRÉREQUIS
###############################################
validate_system_requirements() {
    # Vérifier la préparation du système
    log_info "Vérification des prérequis système..."

    # Vérification des privilèges root
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Privilèges root requis"
        exit 1
    fi

    # Préparer le répertoire de stockage des logs
    mkdir -p "$LOG_STORAGE_PATH"

    # Vérifier la version du noyau (4.0+)
    local kernel_version=$(uname -r | cut -d. -f1)
    if [[ $kernel_version -lt 4 ]]; then
        log_error "Noyau 4.0+ requis pour eBPF (trouvé: $(uname -r))"
        exit 1
    fi

    log_success "Système prêt — Noyau $(uname -r)"
}

###############################################
# GESTIONNAIRE D'ARRÊT
###############################################
shutdown_tracing() {
    # Arrêt du traçage et nettoyage
    log_info "Arrêt du traçage eBPF..."

    # Nettoyer eBPF s'il a été initialisé
    if [[ "$EBPF_ENABLED" == "1" ]]; then
        if bash "$EBPF_PROGRAM_PATH" cleanup; then
            log_success "Nettoyage eBPF complété"
        else
            log_error "Erreur lors du nettoyage eBPF"
        fi
    fi

    log_success "Arrêt complété"
}

# Enregistrer le nettoyage pour les signaux d'interruption
trap shutdown_tracing INT TERM EXIT

###############################################
# EXÉCUTION PRINCIPALE
###############################################
main() {
    # Fonction principale du programme
    echo "CHABAHROOT M1 - SURVEILLANCE DU NOYAU (eBPF)"
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
