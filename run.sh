#!/usr/bin/env bash
# ============================================================
# ChabahRoot - Module : run.sh
# Description : Orchestrateur principal du moteur Analyste Cyber
#               Démarre, gère et arrête les modules défensif
#               et offensif selon la configuration.
# Auteur : Module Analyste Cyber
# Version : 1.0.0
# Usage : ./run.sh [--defensive-only | --offensive-only | --help]
# ============================================================

# Répertoire du script (chemin absolu, robuste aux symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Charger la configuration ---
source "$SCRIPT_DIR/rules.conf" || {
    echo "[ERREUR FATALE] Impossible de charger rules.conf" >&2
    exit 1
}

# --- Charger le logger ---
source "$SCRIPT_DIR/logger.sh" || {
    echo "[ERREUR FATALE] Impossible de charger logger.sh" >&2
    exit 1
}

# --- PID du processus défensif en arrière-plan ---
DEFENSIVE_PID=""

# -------------------------------------------------------
# Fonction : show_banner
# Description : Affiche la bannière du projet
# -------------------------------------------------------
show_banner() {
    echo -e "\033[0;31m"
    cat << 'EOF'
  ██████╗██╗  ██╗ █████╗ ██████╗  █████╗ ██╗  ██╗
 ██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗██║  ██║
 ██║     ███████║███████║██████╔╝███████║███████║
 ██║     ██╔══██║██╔══██║██╔══██╗██╔══██║██╔══██║
 ╚██████╗██║  ██║██║  ██║██████╔╝██║  ██║██║  ██║
  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
EOF
    echo -e "\033[0;33m"
    echo "   ██████╗  ██████╗  ██████╗ ████████╗"
    echo "   ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝"
    echo "   ██████╔╝██║   ██║██║   ██║   ██║"
    echo "   ██╔══██╗██║   ██║██║   ██║   ██║"
    echo "   ██║  ██║╚██████╔╝╚██████╔╝   ██║"
    echo "   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚═╝"
    echo -e "\033[0m"
    echo -e "\033[0;36m  Projet : $PROJECT_NAME | Module : $MODULE_NAME | v$VERSION\033[0m"
    echo -e "\033[0;36m  Logs   : $LOG_FILE\033[0m"
    echo ""
}

# -------------------------------------------------------
# Fonction : show_help
# Description : Affiche l'aide et les options disponibles
# -------------------------------------------------------
show_help() {
    cat << EOF
Usage : $0 [OPTIONS]

OPTIONS :
  --defensive-only    Lance uniquement le module défensif (surveillance continue)
  --offensive-only    Lance uniquement le module offensif (scan one-shot)
  --no-offensive      Lance le module défensif sans scan offensif
  --help, -h          Affiche cette aide

EXEMPLES :
  sudo ./run.sh                    # Mode complet (défensif + offensif)
  sudo ./run.sh --defensive-only   # Surveillance continue uniquement
  sudo ./run.sh --offensive-only   # Audit one-shot uniquement
  sudo ./run.sh --no-offensive     # Défensif sans audit offensif

FICHIERS :
  rules.conf      Configuration des règles et paramètres
  logger.sh       Module de journalisation
  defensive.sh    Module de surveillance défensive
  offensive.sh    Module d'audit offensif
  $LOG_FILE       Fichier de log principal

EOF
}

# -------------------------------------------------------
# Fonction : check_dependencies
# Description : Vérifie que les dépendances sont présentes
# -------------------------------------------------------
check_dependencies() {
    log_info "SYSTEM" "Vérification des dépendances..."
    local missing=0
    local deps="ps grep awk find"

    for dep in $deps; do
        if ! command -v "$dep" &>/dev/null; then
            log_alert "SYSTEM" "Dépendance manquante : $dep"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        log_alert "SYSTEM" "$missing dépendance(s) manquante(s) — arrêt"
        exit 1
    fi

    log_info "SYSTEM" "Toutes les dépendances sont disponibles"
}

# -------------------------------------------------------
# Fonction : check_scripts
# Description : Vérifie que les scripts modules existent
# -------------------------------------------------------
check_scripts() {
    log_info "SYSTEM" "Vérification des modules..."
    local all_ok=1

    for script in defensive.sh offensive.sh logger.sh; do
        local path="$SCRIPT_DIR/$script"
        if [[ ! -f "$path" ]]; then
            log_alert "SYSTEM" "Module manquant : $path"
            all_ok=0
        else
            chmod +x "$path"
            log_debug "SYSTEM" "Module OK : $path"
        fi
    done

    if [[ $all_ok -eq 0 ]]; then
        log_alert "SYSTEM" "Modules manquants — arrêt"
        exit 1
    fi
}

# -------------------------------------------------------
# Fonction : cleanup
# Description : Nettoyage à l'arrêt du moteur (signal trap)
# -------------------------------------------------------
cleanup() {
    echo ""
    log_warn "SYSTEM" "Signal d'arrêt reçu — Arrêt du moteur ChabahRoot..."

    # Arrête le module défensif s'il tourne en arrière-plan
    if [[ -n "$DEFENSIVE_PID" ]] && kill -0 "$DEFENSIVE_PID" 2>/dev/null; then
        log_info "SYSTEM" "Arrêt du module défensif (PID=$DEFENSIVE_PID)..."
        kill "$DEFENSIVE_PID" 2>/dev/null
        wait "$DEFENSIVE_PID" 2>/dev/null
    fi

    # Nettoie les fichiers temporaires
    rm -f /dev/shm/chabah_seen_pids.tmp /dev/shm/chabah_cycle.tmp 2>/dev/null

    log_separator "SESSION TERMINÉE"
    log_info "SYSTEM" "ChabahRoot arrêté proprement. Log : $LOG_FILE"
    exit 0
}

# -------------------------------------------------------
# Fonction : start_defensive_background
# Description : Lance le module défensif en arrière-plan
# -------------------------------------------------------
start_defensive_background() {
    log_info "SYSTEM" "Démarrage du module défensif en arrière-plan..."

    # Source le module défensif et lance la boucle en sous-shell
    (
        source "$SCRIPT_DIR/defensive.sh"
        defensive_init
        while true; do
            run_defensive_cycle
            sleep "$POLL_INTERVAL"
        done
    ) &

    DEFENSIVE_PID=$!
    log_info "SYSTEM" "Module défensif démarré (PID=$DEFENSIVE_PID)"
}

# -------------------------------------------------------
# Fonction : start_offensive_scan
# Description : Lance le module offensif (one-shot)
# -------------------------------------------------------
start_offensive_scan() {
    log_info "SYSTEM" "Démarrage du scan offensif..."
    source "$SCRIPT_DIR/offensive.sh"
    offensive_init
    run_offensive_scan
}

# -------------------------------------------------------
# PROGRAMME PRINCIPAL
# -------------------------------------------------------
main() {
    local mode="full"

    # --- Parsing des arguments ---
    for arg in "$@"; do
        case "$arg" in
            --defensive-only) mode="defensive" ;;
            --offensive-only)  mode="offensive"  ;;
            --no-offensive)    mode="no-offensive" ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "[ERREUR] Argument inconnu : $arg" >&2
                show_help
                exit 1
                ;;
        esac
    done

    # --- Affiche la bannière ---
    show_banner

    # --- Initialise le fichier de log ---
    init_log || exit 1

    log_info "SYSTEM" "Démarrage de ChabahRoot — Mode : $mode"
    log_info "SYSTEM" "PID principal : $$ | Hôte : $(hostname)"

    # --- Vérifie les prérequis ---
    check_dependencies
    check_scripts

    # --- Enregistre le handler de nettoyage sur CTRL+C / SIGTERM ---
    trap cleanup INT TERM

    # --- Lance les modules selon le mode ---
    case "$mode" in
        full)
            start_defensive_background
            sleep 1  # Laisse le module défensif s'initialiser
            start_offensive_scan
            log_info "SYSTEM" "Moteur complet actif — CTRL+C pour arrêter"
            wait "$DEFENSIVE_PID"
            ;;
        defensive)
            source "$SCRIPT_DIR/defensive.sh"
            defensive_init
            log_info "SYSTEM" "Surveillance défensive active — CTRL+C pour arrêter"
            while true; do
                run_defensive_cycle
                sleep "$POLL_INTERVAL"
            done
            ;;
        offensive)
            start_offensive_scan
            ;;
        no-offensive)
            source "$SCRIPT_DIR/defensive.sh"
            defensive_init
            log_info "SYSTEM" "Mode défensif sans offensif — CTRL+C pour arrêter"
            while true; do
                run_defensive_cycle
                sleep "$POLL_INTERVAL"
            done
            ;;
    esac

    cleanup
}

# --- Lance le programme principal avec tous les arguments ---
main "$@"
