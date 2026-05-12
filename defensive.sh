#!/usr/bin/env bash
# ============================================================
# ChabahRoot - Module : defensive.sh
# Description : Détection des transitions UID vers UID 0 (ROOT)
#               et surveillance des processus suspects
# Auteur : Module Analyste Cyber
# Version : 1.0.0
# ============================================================

# Charger la configuration et le logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/rules.conf" || {
    echo "[ERREUR] Impossible de charger rules.conf" >&2
    exit 1
}

source "$SCRIPT_DIR/logger.sh" || {
    echo "[ERREUR] Impossible de charger logger.sh" >&2
    exit 1
}

# --- Fichier temporaire pour suivre les PIDs déjà détectés ---
TMP_DIR="./tmp"
mkdir -p "$TMP_DIR"
SEEN_PIDS_FILE="$TMP_DIR/chabah_seen_pids.tmp"

# -------------------------------------------------------
# Fonction : defensive_init
# Description : Initialise le module défensif
# -------------------------------------------------------
defensive_init() {
    log_info "DEFENSIVE" "Initialisation du module défensif..."

    # Crée le fichier de suivi des PIDs s'il n'existe pas
    touch "$SEEN_PIDS_FILE" 2>/dev/null || {
        log_warn "DEFENSIVE" "Impossible de créer le fichier PID temporaire : $SEEN_PIDS_FILE"
    }

    log_info "DEFENSIVE" "Surveillance UID cible : $TARGET_UID (ROOT)"
    log_info "DEFENSIVE" "Intervalle de polling : ${POLL_INTERVAL}s"
    log_separator "MODULE DEFENSIF ACTIF"
}

# -------------------------------------------------------
# Fonction : detect_uid_escalation
# Description : Scanne tous les processus en cours et détecte
#               ceux qui tournent sous UID 0 (root)
# -------------------------------------------------------
detect_uid_escalation() {
    log_debug "DEFENSIVE" "Scan des processus en cours..."

    # Récupère la liste : UID PID PPID CMD
    # ps -eo uid,pid,ppid,comm : liste tous les processus
    while IFS= read -r line; do
        local uid pid ppid cmd
        read -r uid pid ppid cmd <<< "$line"

        # Vérifie si l'UID correspond à la cible (root = 0)
        if [[ "$uid" -eq "$TARGET_UID" ]]; then

            # Ignore les PIDs déjà signalés pour éviter le spam
            if grep -q "^${pid}$" "$SEEN_PIDS_FILE" 2>/dev/null; then
                continue
            fi

            # Enregistre le PID comme déjà vu
            echo "$pid" >> "$SEEN_PIDS_FILE"

            # Construit le message d'alerte
            local alert_msg="Transition ROOT détectée ! PID=$pid | PPID=$ppid | CMD=$cmd | UID=$uid"
            log_alert "DEFENSIVE" "$alert_msg"

            # Analyse le nom du processus pour détecter des outils suspects
            check_suspicious_process "$pid" "$cmd"
        fi

    done < <(ps -eo uid,pid,ppid,comm --no-headers 2>/dev/null)
}

# -------------------------------------------------------
# Fonction : check_suspicious_process
# Description : Vérifie si un processus root utilise des
#               outils connus d'escalade de privilèges
# Arguments : $1 - PID, $2 - nom du processus
# -------------------------------------------------------
check_suspicious_process() {
    local pid="$1"
    local cmd="$2"

    # Liste des outils suspects fréquemment utilisés en escalade
    local suspicious_tools="sudo su bash sh python python3 perl ruby nc ncat netcat socat wget curl"

    for tool in $suspicious_tools; do
        if [[ "$cmd" == "$tool" ]]; then
            log_alert "DEFENSIVE" "Processus suspect root identifié : '$cmd' (PID=$pid) — Outil potentiellement dangereux"
            return 0
        fi
    done
}

# -------------------------------------------------------
# Fonction : scan_env_variables
# Description : Analyse les variables d'environnement du
#               processus actuel pour détecter des secrets
# -------------------------------------------------------
scan_env_variables() {
    log_info "DEFENSIVE" "Analyse des variables d'environnement..."

    # Lit les variables d'environnement du processus courant
    # /proc/self/environ : variables du processus actuel (nullbyte-separated)
    if [[ -r /proc/self/environ ]]; then
        local env_content
        env_content=$(tr '\0' '\n' < /proc/self/environ 2>/dev/null)

        # Filtre les mots-clés sensibles dans les variables d'env
        while IFS= read -r env_var; do
            filter_sensitive "$env_var"
        done <<< "$env_content"
    else
        log_warn "DEFENSIVE" "/proc/self/environ non lisible (accès restreint)"
    fi
}

# -------------------------------------------------------
# Fonction : scan_cmdlines
# Description : Analyse les lignes de commande des processus
#               root pour détecter des arguments sensibles
# -------------------------------------------------------
scan_cmdlines() {
    log_info "DEFENSIVE" "Analyse des lignes de commande des processus root..."

    # Parcourt tous les processus root dans /proc
    for pid_dir in /proc/[0-9]*/; do
        local pid
        pid=$(basename "$pid_dir")

        # Vérifie que le fichier status est lisible
        local status_file="${pid_dir}status"
        [[ -r "$status_file" ]] || continue

        # Récupère l'UID réel du processus
        local proc_uid
        proc_uid=$(grep -m1 "^Uid:" "$status_file" 2>/dev/null | awk '{print $2}')

        # Analyse uniquement les processus root
        if [[ "$proc_uid" == "0" ]]; then
            local cmdline_file="${pid_dir}cmdline"
            if [[ -r "$cmdline_file" ]]; then
                # Remplace les nullbytes par des espaces pour la lisibilité
                local cmdline
                cmdline=$(tr '\0' ' ' < "$cmdline_file" 2>/dev/null | head -c 200)
                filter_sensitive "$cmdline"
            fi
        fi
    done
}

# -------------------------------------------------------
# Fonction : purge_seen_pids
# Description : Nettoie les PIDs qui ne sont plus actifs
#               pour éviter une croissance infinie du fichier
# -------------------------------------------------------
purge_seen_pids() {
    [[ -f "$SEEN_PIDS_FILE" ]] || return 0

    local temp_file="${SEEN_PIDS_FILE}.tmp"
    > "$temp_file"

    while IFS= read -r pid; do
        # Vérifie si le processus est toujours actif
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid" >> "$temp_file"
        fi
    done < "$SEEN_PIDS_FILE"

    mv "$temp_file" "$SEEN_PIDS_FILE" 2>/dev/null
    log_debug "DEFENSIVE" "Purge des PIDs terminés effectuée"
}

# -------------------------------------------------------
# Fonction : run_defensive_cycle
# Description : Exécute un cycle complet d'analyse défensive
# -------------------------------------------------------
run_defensive_cycle() {
    log_debug "DEFENSIVE" "--- Nouveau cycle défensif ---"

    # 1. Détection des transitions root
    detect_uid_escalation

    # 2. Scan des variables d'environnement
    scan_env_variables

    # 3. Scan des lignes de commande des processus root
    scan_cmdlines

    # 4. Nettoyage périodique (tous les 10 cycles)
    local cycle_count_file="$TMP_DIR/chabah_cycle.tmp"
    local cycle=0
    [[ -f "$cycle_count_file" ]] && cycle=$(cat "$cycle_count_file" 2>/dev/null)
    cycle=$((cycle + 1))
    echo "$cycle" > "$cycle_count_file"

    if (( cycle % 10 == 0 )); then
        purge_seen_pids
    fi
}

# -------------------------------------------------------
# Point d'entrée si exécuté directement
# -------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    defensive_init
    log_info "DEFENSIVE" "Démarrage de la boucle de surveillance..."

    while true; do
        run_defensive_cycle
        sleep "$POLL_INTERVAL"
    done
fi
