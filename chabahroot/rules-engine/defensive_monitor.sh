#!/usr/bin/env bash
# ChabahRoot M2 - Surveillance defensive
# Auteur: Equipe Cyber
# Detecte les elevations de privileges et les processus suspects
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../shared/rules.conf"" || exit 1
source "$SCRIPT_DIR/../shared/logger.sh"" || exit 1

readonly SEEN_PIDS_FILE="$PROJECT_ROOT/detection/tmp/seen_pids.tmp"

defensive_init() {
    log_info "DEFENSIVE" "Initialisation du module defensif"
    mkdir -p "$(dirname "$SEEN_PIDS_FILE")"
    touch "$SEEN_PIDS_FILE" 2>/dev/null || {
        log_warn "DEFENSIVE" "Impossible de creer le fichier de suivi PID"
    }
    log_info "DEFENSIVE" "UID cible: $TARGET_UID | Intervalle: ${POLL_INTERVAL}s"
}

detect_uid_escalation() {
    log_debug "DEFENSIVE" "Analyse des elevations de privileges..."
    
    while IFS= read -r uid pid ppid cmd; do
        [[ "$uid" -eq "$TARGET_UID" ]] || continue
        
        if grep -q "^${pid}$" "$SEEN_PIDS_FILE" 2>/dev/null; then
            continue
        fi
        
        echo "$pid" >> "$SEEN_PIDS_FILE"
        
        local msg="Elevation detectee: PID=$pid PPID=$ppid CMD=$cmd"
        log_alert "DEFENSIVE" "$msg"
        
        check_suspicious_process "$cmd"
        
    done < <(ps -eo uid,pid,ppid,comm --no-headers 2>/dev/null)
}

check_suspicious_process() {
    local cmd="$1"
    local suspicious="nc ncat netcat bash sh perl python ruby"
    
    for suspect in $suspicious; do
        if [[ "$cmd" == "$suspect"* ]]; then
            log_alert "DEFENSIVE" "Processus suspect detecte: $cmd"
            break
        fi
    done
}

# Execute un cycle defensif
run_defensive_cycle() {
    detect_uid_escalation
}

# Exporte les fonctions pour l orchestrateur
export -f defensive_init run_defensive_cycle detect_uid_escalation check_suspicious_process
