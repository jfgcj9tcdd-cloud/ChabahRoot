#!/usr/bin/env bash
# ChabahRoot M2 - Audit offensif
# Auteur: Équipe Cyber
# Evalue les vecteurs d elevation et les lacunes de durcissement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../shared/rules.conf"" || exit 1
source "$SCRIPT_DIR/../shared/logger.sh"" || exit 1

# Initialise le module offensif
offensive_init() {
    log_info "OFFENSIVE" "Initialisation du module d audit"
    log_warn "OFFENSIVE" "MODE AUDIT - usage autorise uniquement"
}

# Audite les binaires SUID
audit_suid_binaries() {
    log_info "OFFENSIVE" "Analyse des binaires SUID..."
    
    local whitelist="sudo su passwd ping mount umount newgrp chsh chfn"
    
    while IFS= read -r binary; do
        local bin_name
        bin_name=$(basename "$binary")
        
        if [[ ! " $whitelist " =~ " $bin_name " ]]; then
            log_alert "OFFENSIVE" "Binaire SUID non standard: $binary"
        else
            log_debug "OFFENSIVE" "SUID connu: $binary"
        fi
    done < <(find /usr /bin /sbin /tmp /opt -perm -4000 -type f 2>/dev/null)
}

# Detecte les fichiers world-writable sensibles
audit_world_writable() {
    log_info "OFFENSIVE" "Analyse des fichiers world-writable..."
    
    while IFS= read -r file; do
        log_alert "OFFENSIVE" "Fichier world-writable en chemin critique: $file"
    done < <(find /etc /usr/bin /usr/sbin /bin /sbin -perm -0002 -type f 2>/dev/null)
}

# Analyse la configuration sudoers
check_sudoers() {
    log_info "OFFENSIVE" "Analyse de la configuration sudoers..."
    
    [[ ! -r /etc/sudoers ]] && {
        log_warn "OFFENSIVE" "Fichier sudoers non lisible"
        return 0
    }
    
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        if echo "$line" | grep -qi "NOPASSWD"; then
            log_alert "OFFENSIVE" "Regle sudoers dangereuse (NOPASSWD): $line"
        fi
        
        if echo "$line" | grep -qi "ALL=(ALL)"; then
            log_alert "OFFENSIVE" "Regle sudoers dangereuse (acces total): $line"
        fi
    done < /etc/sudoers
}

# Lance l audit complet
run_offensive_scan() {
    log_separator "DEMARRAGE AUDIT SECURITE"
    audit_suid_binaries
    audit_world_writable
    check_sudoers
    log_separator "AUDIT TERMINE"
}

# Exporte les fonctions pour l orchestrateur
export -f offensive_init run_offensive_scan audit_suid_binaries audit_world_writable check_sudoers
