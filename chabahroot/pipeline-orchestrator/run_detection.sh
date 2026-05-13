#!/usr/bin/env bash
# ChabahRoot - Orchestrateur de detection
# Auteur: Equipe Cyber
# Gere la surveillance defensive et les audits de securite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../shared/rules.conf"" >&2; exit 1; }
source "$SCRIPT_DIR/../shared/logger.sh"" >&2; exit 1; }

DEFENSIVE_PID=""

check_prerequisites() {
    log_info "SYSTEM" "Verification des prerequis..."
    
    local deps="ps grep awk find"
    for cmd in $deps; do
        command -v "$cmd" &>/dev/null || {
            log_alert "SYSTEM" "Commande requise absente: $cmd"
            return 1
        }
    done
    
    for script in "$PROJECT_ROOT/services/m2_detection/defensive_monitor.sh" "$PROJECT_ROOT/services/m2_detection/offensive_audit.sh"; do
        [[ -f "$script" ]] || {
            log_alert "SYSTEM" "Module requis absent: $script"
            return 1
        }
        chmod +x "$script"
    done
}

# Gere l arret propre sur signal
cleanup() {
    echo ""
    log_warn "SYSTEM" "Signal d'arret recu - arret du moteur de detection"
    
    # Arrete le module defensif si besoin
    if [[ -n "$DEFENSIVE_PID" ]] && kill -0 "$DEFENSIVE_PID" 2>/dev/null; then
        log_info "SYSTEM" "Arret du module defensif (PID=$DEFENSIVE_PID)"
        kill "$DEFENSIVE_PID" 2>/dev/null
        wait "$DEFENSIVE_PID" 2>/dev/null || true
    fi
    
    # Nettoie les fichiers temporaires
    rm -f "$PROJECT_ROOT/detection/tmp/"* 2>/dev/null || true
    
    log_separator "SESSION TERMINEE"
    log_info "SYSTEM" "Moteur de detection arrete. Log: $LOG_FILE"
    exit 0
}

trap cleanup INT TERM EXIT

# Demarre le module defensif en arriere-plan
start_defensive_background() {
    log_info "SYSTEM" "Demarrage du monitoring defensif en arriere-plan"
    
    (
        source "$PROJECT_ROOT/services/m2_detection/defensive_monitor.sh"
        defensive_init
        while true; do
            run_defensive_cycle
            sleep "$POLL_INTERVAL"
        done
    ) &
    
    DEFENSIVE_PID=$!
    log_info "SYSTEM" "Module defensif demarre (PID=$DEFENSIVE_PID)"
}

# Lance un audit offensif en execution unique
run_offensive_audit() {
    log_info "SYSTEM" "Demarrage de l'audit securite"
    source "$PROJECT_ROOT/services/m2_detection/offensive_audit.sh"
    offensive_init
    run_offensive_scan
}

# Affiche l aide
show_help() {
    cat << 'EOF'
Moteur de detection ChabahRoot

Usage: ./run.sh [OPTIONS]

OPTIONS:
  --defensive-only    Demarre seulement la surveillance defensive
  --offensive-only    Lance seulement l audit securite
  --no-offensive      Demarre la surveillance sans audit
  --help              Affiche cette aide

EXEMPLES:
  sudo ./run.sh                      # Mode complet (defensif + audit)
  sudo ./run.sh --defensive-only     # Surveillance continue seulement
  sudo ./run.sh --offensive-only     # Audit securite seulement
  sudo ./run.sh --no-offensive       # Surveillance sans audit

FICHIERS:
  services/shared/rules.conf                  Parametres de configuration
  services/shared/logger.sh                   Module de journalisation
  services/m2_detection/defensive_monitor.sh Module de surveillance defensive
  services/m2_detection/offensive_audit.sh   Module d audit offensif
  logs/chabah.log                             Journal principal

EOF
}

# Point d entree principal
main() {
    local mode="full"
    
    # Analyse les arguments
    for arg in "$@"; do
        case "$arg" in
            --defensive-only) mode="defensive_only" ;;
            --offensive-only) mode="offensive_only" ;;
            --no-offensive) mode="defensive_only" ;;
            --help|-h) show_help; exit 0 ;;
        esac
    done
    
    # Verifie les prerequis
    check_prerequisites || exit 1
    
    # Initialise la journalisation
    init_log || exit 1
    
    log_separator "DEMARRAGE DU MOTEUR DE DETECTION CHABAHROOT"
    log_info "SYSTEM" "Mode: $mode | Log: $LOG_FILE"
    
    # Execute selon le mode choisi
    case "$mode" in
        offensive_only)
            run_offensive_audit
            exit 0
            ;;
        defensive_only)
            start_defensive_background
            ;;
        full)
            start_defensive_background
            run_offensive_audit
            ;;
    esac
    
    # Garde le module defensif actif
    if [[ -n "$DEFENSIVE_PID" ]]; then
        log_info "SYSTEM" "Detection active - Ctrl+C pour arreter"
        wait "$DEFENSIVE_PID" 2>/dev/null || true
    fi
}

main "$@"
