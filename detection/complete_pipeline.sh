#!/usr/bin/env bash
# ChabahRoot — Orchestrateur Complet du Pipeline (M1→M2→M3→M4)
# Gère le cycle de vie complet: Kernel → Transport → Analysis → Output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/rules.conf"

readonly M1_DIR="$SCRIPT_DIR/../chabahroot/m1"
readonly M1_INIT="$M1_DIR/m1_complete.sh"
readonly M3_READER="$SCRIPT_DIR/ringbuf_reader.sh"
readonly M2_RULES="$SCRIPT_DIR/rules_engine.sh"
readonly M4_TESTS="$SCRIPT_DIR/m4_integration_tests.sh"

readonly PIPELINE_STATE="/tmp/chabah_pipeline_state"
readonly EVENT_PIPE="$SCRIPT_DIR/event_stream.pipe"

# État des processus
M1_PID=""
M3_PID=""
M2_PID=""

# Initialiser l'environnement du pipeline
init_pipeline() {
    log_info "PIPELINE" "Initialisation du pipeline complet ChabahRoot"
    
    mkdir -p "$PIPELINE_STATE"
    mkdir -p "$(dirname "$EVENT_PIPE")"
    
    # Créer une FIFO pour le streaming d'événements M3→M2
    if [[ ! -p "$EVENT_PIPE" ]]; then
        mkfifo "$EVENT_PIPE" 2>/dev/null || {
            log_warn "PIPELINE" "Impossible de créer FIFO (peut exister)"
        }
    fi
    
    # Rendre les scripts exécutables
    chmod +x "$M1_INIT" "$M3_READER" "$M2_RULES" "$M4_TESTS" 2>/dev/null || true
    
    log_success "PIPELINE" "Environnement du pipeline initialisé"
}

# Vérifier les prérequis du pipeline
verify_pipeline_prerequisites() {
    log_info "PIPELINE" "Vérification des prérequis du pipeline"
    
    # Vérifier que l'utilisateur est root (M1 le nécessite)
    if [[ $EUID -ne 0 ]]; then
        log_error "PIPELINE" "Le pipeline requiert des privilèges root (pour M1 eBPF)"
        return 1
    fi
    
    # Vérifier les scripts essentiels
    local required_scripts=(
        "$M1_INIT"
        "$M3_READER"
        "$M2_RULES"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "PIPELINE" "Script manquant: $script"
            return 1
        fi
    done
    
    # Vérifier les fichiers de configuration
    if [[ ! -f "$SCRIPT_DIR/detection_rules.json" ]]; then
        log_warn "PIPELINE" "Fichier de règles non trouvé: detection_rules.json"
    fi
    
    log_success "PIPELINE" "Tous les prérequis du pipeline vérifiés"
}

# Lancer la couche M1 (Ingestion eBPF)
start_m1_ingestion() {
    log_info "PIPELINE" "Démarrage de M1 (Ingestion eBPF/Kernel)"
    
    bash "$M1_INIT" start >/dev/null 2>&1 &
    M1_PID=$!
    
    # Attendre que M1 soit prêt
    sleep 2
    
    if kill -0 "$M1_PID" 2>/dev/null; then
        log_success "PIPELINE" "M1 démarré (PID=$M1_PID)"
        echo "$M1_PID" > "$PIPELINE_STATE/m1.pid"
        return 0
    else
        log_error "PIPELINE" "Échec du démarrage de M1"
        return 1
    fi
}

# Lancer la couche M3 (Normalisation) en arrière-plan
start_m3_transport() {
    log_info "PIPELINE" "Démarrage de M3 (Transport/Normalisation)"
    
    # M3 lit depuis le ring buffer et écrit vers M2 via la FIFO
    bash "$M3_READER" > "$EVENT_PIPE" 2>"$PIPELINE_STATE/m3.log" &
    M3_PID=$!
    
    # Attendre que M3 soit prêt
    sleep 1
    
    if kill -0 "$M3_PID" 2>/dev/null; then
        log_success "PIPELINE" "M3 démarré (PID=$M3_PID)"
        echo "$M3_PID" > "$PIPELINE_STATE/m3.pid"
        return 0
    else
        log_error "PIPELINE" "Échec du démarrage de M3"
        return 1
    fi
}

# Lancer la couche M2 (Analysis/Rules) en arrière-plan
start_m2_analysis() {
    log_info "PIPELINE" "Démarrage de M2 (Analyse/Règles)"
    
    # M2 lit depuis M3 (FIFO) et génère des alertes
    bash "$M2_RULES" < "$EVENT_PIPE" > "$PIPELINE_STATE/alerts.log" 2>&1 &
    M2_PID=$!
    
    # Attendre que M2 soit prêt
    sleep 1
    
    if kill -0 "$M2_PID" 2>/dev/null; then
        log_success "PIPELINE" "M2 démarré (PID=$M2_PID)"
        echo "$M2_PID" > "$PIPELINE_STATE/m2.pid"
        return 0
    else
        log_error "PIPELINE" "Échec du démarrage de M2"
        return 1
    fi
}

# Stopper le pipeline
stop_pipeline() {
    log_info "PIPELINE" "Arrêt du pipeline"
    
    # Arrêter M2 (Analysis)
    if [[ -f "$PIPELINE_STATE/m2.pid" ]]; then
        local m2_pid
        m2_pid=$(cat "$PIPELINE_STATE/m2.pid" 2>/dev/null || echo "")
        if [[ -n "$m2_pid" ]] && kill -0 "$m2_pid" 2>/dev/null; then
            log_info "PIPELINE" "Arrêt de M2 (PID=$m2_pid)"
            kill "$m2_pid" 2>/dev/null || true
            wait "$m2_pid" 2>/dev/null || true
        fi
    fi
    
    # Arrêter M3 (Transport)
    if [[ -f "$PIPELINE_STATE/m3.pid" ]]; then
        local m3_pid
        m3_pid=$(cat "$PIPELINE_STATE/m3.pid" 2>/dev/null || echo "")
        if [[ -n "$m3_pid" ]] && kill -0 "$m3_pid" 2>/dev/null; then
            log_info "PIPELINE" "Arrêt de M3 (PID=$m3_pid)"
            kill "$m3_pid" 2>/dev/null || true
            wait "$m3_pid" 2>/dev/null || true
        fi
    fi
    
    # Arrêter M1 (Ingestion)
    if [[ -f "$PIPELINE_STATE/m1.pid" ]]; then
        local m1_pid
        m1_pid=$(cat "$PIPELINE_STATE/m1.pid" 2>/dev/null || echo "")
        if [[ -n "$m1_pid" ]] && kill -0 "$m1_pid" 2>/dev/null; then
            log_info "PIPELINE" "Arrêt de M1 (PID=$m1_pid)"
            bash "$M1_INIT" stop >/dev/null 2>&1 || true
            kill "$m1_pid" 2>/dev/null || true
            wait "$m1_pid" 2>/dev/null || true
        fi
    fi
    
    # Nettoyer les fichiers temporaires
    rm -f "$EVENT_PIPE" 2>/dev/null || true
    
    log_success "PIPELINE" "Pipeline arrêté"
}

# Afficher le statut du pipeline
show_status() {
    log_separator "État du Pipeline ChabahRoot"
    
    local overall_status="RUNNING"
    
    # Vérifier M1
    if [[ -f "$PIPELINE_STATE/m1.pid" ]]; then
        local m1_pid
        m1_pid=$(cat "$PIPELINE_STATE/m1.pid")
        if kill -0 "$m1_pid" 2>/dev/null; then
            log_info "STATUS" "M1 (Ingestion):       ✓ RUNNING (PID=$m1_pid)"
        else
            log_error "STATUS" "M1 (Ingestion):       ✗ STOPPED"
            overall_status="DEGRADED"
        fi
    else
        log_warn "STATUS" "M1 (Ingestion):       ? UNKNOWN"
    fi
    
    # Vérifier M3
    if [[ -f "$PIPELINE_STATE/m3.pid" ]]; then
        local m3_pid
        m3_pid=$(cat "$PIPELINE_STATE/m3.pid")
        if kill -0 "$m3_pid" 2>/dev/null; then
            log_info "STATUS" "M3 (Transport):       ✓ RUNNING (PID=$m3_pid)"
        else
            log_error "STATUS" "M3 (Transport):       ✗ STOPPED"
            overall_status="DEGRADED"
        fi
    else
        log_warn "STATUS" "M3 (Transport):       ? UNKNOWN"
    fi
    
    # Vérifier M2
    if [[ -f "$PIPELINE_STATE/m2.pid" ]]; then
        local m2_pid
        m2_pid=$(cat "$PIPELINE_STATE/m2.pid")
        if kill -0 "$m2_pid" 2>/dev/null; then
            log_info "STATUS" "M2 (Analysis):        ✓ RUNNING (PID=$m2_pid)"
        else
            log_error "STATUS" "M2 (Analysis):        ✗ STOPPED"
            overall_status="DEGRADED"
        fi
    else
        log_warn "STATUS" "M2 (Analysis):        ? UNKNOWN"
    fi
    
    # Statut global
    log_separator "Overall Status"
    log_info "STATUS" "Pipeline Status: $overall_status"
    log_info "STATUS" "Log File: $LOG_FILE"
}

# Handler de signal pour arrêt gracieux
cleanup() {
    echo ""
    log_warn "PIPELINE" "Signal d'arrêt reçu"
    stop_pipeline
    log_separator "ARRÊT COMPLET"
    exit 0
}

# Lancer le pipeline complet
run_pipeline() {
    log_separator "Démarrage du Pipeline ChabahRoot (M1→M2→M3→M4)"
    
    trap cleanup INT TERM EXIT
    
    init_pipeline || exit 1
    verify_pipeline_prerequisites || exit 1
    
    start_m1_ingestion || exit 1
    start_m3_transport || exit 1
    start_m2_analysis || exit 1
    
    log_separator "Pipeline entièrement opérationnel"
    
    # Afficher le statut initial
    show_status
    
    # Boucle principale
    while true; do
        sleep 5
        
        # Vérifier que tous les processus tournent toujours
        local any_dead=false
        
        for pid_file in "$PIPELINE_STATE"/*.pid; do
            [[ -f "$pid_file" ]] || continue
            local pid
            pid=$(cat "$pid_file" 2>/dev/null || echo "")
            
            if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                log_error "PIPELINE" "Processus mort détecté: $(basename "$pid_file")"
                any_dead=true
            fi
        done
        
        if [[ "$any_dead" == "true" ]]; then
            log_error "PIPELINE" "Un ou plusieurs processus sont tombés"
            show_status
            log_info "PIPELINE" "Redémarrage en cours..."
            break
        fi
    done
}

# Programme principal
main() {
    case "${1:-run}" in
        run)
            run_pipeline
            ;;
        start)
            # Démarrer en arrière-plan
            nohup "$0" run >/dev/null 2>&1 &
            log_info "PIPELINE" "Pipeline lancé en arrière-plan (PID=$!)"
            ;;
        stop)
            stop_pipeline
            ;;
        status)
            show_status
            ;;
        test)
            # Lancer les tests M4
            bash "$M4_TESTS" all
            ;;
        *)
            log_info "USAGE" "$0 {run|start|stop|status|test}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
