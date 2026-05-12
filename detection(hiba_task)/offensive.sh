#!/usr/bin/env bash
# ============================================================
# ChabahRoot - Module : offensive.sh
# Description : Analyse offensive — Simulation de détection
#               d'activités suspectes, audit des accès root,
#               et génération d'indicateurs de compromission (IOC)
# Auteur : Module Analyste Cyber
# Version : 1.0.0
# NOTE : Ce module est destiné à un usage légal/défensif
#        dans un cadre de cybersécurité autorisé uniquement.
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

# -------------------------------------------------------
# Fonction : offensive_init
# Description : Initialise le module offensif
# -------------------------------------------------------
offensive_init() {
    log_info "OFFENSIVE" "Initialisation du module offensif..."
    log_warn "OFFENSIVE" "MODE OFFENSIF ACTIF — Usage légal/autorisé uniquement"
    log_separator "MODULE OFFENSIF ACTIF"
}

# -------------------------------------------------------
# Fonction : audit_suid_binaries
# Description : Recherche les binaires SUID qui peuvent
#               permettre une escalade de privilèges
# -------------------------------------------------------
audit_suid_binaries() {
    log_info "OFFENSIVE" "Audit des binaires SUID en cours..."

    # Recherche tous les fichiers avec le bit SUID dans les répertoires standards
    local suid_list
    suid_list=$(find /usr /bin /sbin /tmp /opt -perm -4000 -type f 2>/dev/null)

    if [[ -z "$suid_list" ]]; then
        log_info "OFFENSIVE" "Aucun binaire SUID inhabituel détecté"
        return 0
    fi

    # Binaires SUID légitimes connus (whitelist minimale)
    local whitelist="sudo su passwd ping mount umount newgrp chsh chfn"

    while IFS= read -r binary; do
        local bin_name
        bin_name=$(basename "$binary")
        local is_whitelisted=0

        # Vérifie si le binaire est dans la liste blanche
        for white in $whitelist; do
            if [[ "$bin_name" == "$white" ]]; then
                is_whitelisted=1
                break
            fi
        done

        if [[ "$is_whitelisted" -eq 0 ]]; then
            log_alert "OFFENSIVE" "Binaire SUID non standard détecté : $binary"
        else
            log_debug "OFFENSIVE" "Binaire SUID connu (whitelist) : $binary"
        fi
    done <<< "$suid_list"
}

# -------------------------------------------------------
# Fonction : audit_world_writable
# Description : Détecte les fichiers/dossiers accessibles
#               en écriture par tous (world-writable)
# -------------------------------------------------------
audit_world_writable() {
    log_info "OFFENSIVE" "Recherche des fichiers world-writable..."

    # Cherche dans les répertoires sensibles
    local ww_files
    ww_files=$(find /etc /usr/bin /usr/sbin /bin /sbin -perm -0002 -type f 2>/dev/null)

    if [[ -z "$ww_files" ]]; then
        log_info "OFFENSIVE" "Aucun fichier world-writable critique trouvé"
        return 0
    fi

    while IFS= read -r ww_file; do
        log_alert "OFFENSIVE" "Fichier world-writable dans zone sensible : $ww_file"
    done <<< "$ww_files"
}

# -------------------------------------------------------
# Fonction : check_sudoers
# Description : Analyse le fichier sudoers pour détecter
#               des configurations dangereuses (NOPASSWD, ALL)
# -------------------------------------------------------
check_sudoers() {
    log_info "OFFENSIVE" "Vérification de la configuration sudoers..."

    local sudoers_file="/etc/sudoers"

    if [[ ! -r "$sudoers_file" ]]; then
        log_warn "OFFENSIVE" "Fichier sudoers non accessible (privilèges insuffisants)"
        return 0
    fi

    # Détecte les règles dangereuses : NOPASSWD ou ALL=(ALL)
    while IFS= read -r line; do
        # Ignore les commentaires et les lignes vides
        [[ "$line" =~ ^# ]] && continue
        [[ -z "${line// }" ]] && continue

        if echo "$line" | grep -qi "NOPASSWD"; then
            log_alert "OFFENSIVE" "Règle NOPASSWD détectée dans sudoers : $line"
        fi

        if echo "$line" | grep -qi "ALL=(ALL).*ALL"; then
            log_warn "OFFENSIVE" "Règle ALL=(ALL) détectée dans sudoers : $line"
        fi
    done < "$sudoers_file"
}

# -------------------------------------------------------
# Fonction : check_cron_jobs
# Description : Analyse les crontabs pour détecter des
#               tâches planifiées suspectes en root
# -------------------------------------------------------
check_cron_jobs() {
    log_info "OFFENSIVE" "Analyse des tâches cron root..."

    local cron_dirs="/var/spool/cron/crontabs /etc/cron.d /etc/cron.daily /etc/cron.hourly"

    for cron_dir in $cron_dirs; do
        [[ -d "$cron_dir" ]] || continue

        for cron_file in "$cron_dir"/*; do
            [[ -f "$cron_file" ]] || continue

            # Filtre les mots-clés sensibles dans les crons
            while IFS= read -r line; do
                [[ "$line" =~ ^# ]] && continue
                filter_sensitive "$line"

                # Détecte les téléchargements ou reverse shells dans les crons
                if echo "$line" | grep -qE "(curl|wget|nc |ncat|bash -i|/dev/tcp)"; then
                    log_alert "OFFENSIVE" "Cron suspect détecté dans $cron_file : $(echo "$line" | head -c 100)"
                fi
            done < "$cron_file" 2>/dev/null
        done
    done
}

# -------------------------------------------------------
# Fonction : check_login_history
# Description : Analyse l'historique de connexion pour
#               détecter des connexions root suspectes
# -------------------------------------------------------
check_login_history() {
    log_info "OFFENSIVE" "Analyse de l'historique de connexion..."

    # Vérifie si last est disponible
    if ! command -v last &>/dev/null; then
        log_warn "OFFENSIVE" "Commande 'last' non disponible"
        return 0
    fi

    # Recherche les connexions root récentes
    local root_logins
    root_logins=$(last -n 20 root 2>/dev/null | grep -v "^$" | grep -v "wtmp begins")

    if [[ -z "$root_logins" ]]; then
        log_info "OFFENSIVE" "Aucune connexion root récente dans l'historique"
        return 0
    fi

    while IFS= read -r login_line; do
        log_warn "OFFENSIVE" "Connexion root historique : $login_line"
    done <<< "$root_logins"
}

# -------------------------------------------------------
# Fonction : generate_ioc_report
# Description : Génère un rapport d'indicateurs de
#               compromission (IOC) dans le fichier de log
# -------------------------------------------------------
generate_ioc_report() {
    log_separator "RAPPORT IOC"
    log_info "OFFENSIVE" "Génération du rapport IOC..."

    # Compte les alertes dans le fichier de log
    local alert_count=0
    if [[ -r "$LOG_FILE" ]]; then
        alert_count=$(grep -c "\[ALERT\]" "$LOG_FILE" 2>/dev/null || echo 0)
    fi

    local warn_count=0
    if [[ -r "$LOG_FILE" ]]; then
        warn_count=$(grep -c "\[WARN\]" "$LOG_FILE" 2>/dev/null || echo 0)
    fi

    log_info "OFFENSIVE" "=== RÉSUMÉ IOC ==="
    log_info "OFFENSIVE" "  Alertes critiques : $alert_count"
    log_info "OFFENSIVE" "  Avertissements    : $warn_count"
    log_info "OFFENSIVE" "  Hôte analysé      : $(hostname)"
    log_info "OFFENSIVE" "  Horodatage        : $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "OFFENSIVE" "  Kernel            : $(uname -r)"
    log_info "OFFENSIVE" "  Log enregistré    : $LOG_FILE"

    log_separator "FIN RAPPORT IOC"
}

# -------------------------------------------------------
# Fonction : run_offensive_scan
# Description : Lance un scan offensif complet (one-shot)
# -------------------------------------------------------
run_offensive_scan() {
    log_info "OFFENSIVE" "Démarrage du scan offensif complet..."

    audit_suid_binaries
    audit_world_writable
    check_sudoers
    check_cron_jobs
    check_login_history
    generate_ioc_report

    log_info "OFFENSIVE" "Scan offensif terminé."
}

# -------------------------------------------------------
# Point d'entrée si exécuté directement
# -------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    offensive_init
    run_offensive_scan
fi
