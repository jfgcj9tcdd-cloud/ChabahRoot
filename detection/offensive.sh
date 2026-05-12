#!/usr/bin/env bash
# ChabahRoot — Module d'audit sécurité
# Audit unique de vecteurs d'escalade de privilèges et lacunes de durcissement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/rules.conf" || exit 1
source "$SCRIPT_DIR/logger.sh" || exit 1

# Initialize offensive module
offensive_init() {
    log_info "OFFENSIVE" "Initializing security audit module"
    log_warn "OFFENSIVE" "AUDIT MODE - Legal and authorized use only"
}

# Audit SUID binaries for privilege escalation vectors
audit_suid_binaries() {
    log_info "OFFENSIVE" "Scanning for SUID binaries..."
    
    # Whitelist of known legitimate SUID binaries
    local whitelist="sudo su passwd ping mount umount newgrp chsh chfn"
    
    while IFS= read -r binary; do
        local bin_name
        bin_name=$(basename "$binary")
        
        # Check if binary is in whitelist
        if [[ ! " $whitelist " =~ " $bin_name " ]]; then
            log_alert "OFFENSIVE" "Non-standard SUID binary: $binary"
        else
            log_debug "OFFENSIVE" "Known SUID (whitelisted): $binary"
        fi
    done < <(find /usr /bin /sbin /tmp /opt -perm -4000 -type f 2>/dev/null)
}

# Detect world-writable files in sensitive directories
audit_world_writable() {
    log_info "OFFENSIVE" "Scanning for world-writable files in sensitive paths..."
    
    while IFS= read -r file; do
        log_alert "OFFENSIVE" "World-writable file in critical directory: $file"
    done < <(find /etc /usr/bin /usr/sbin /bin /sbin -perm -0002 -type f 2>/dev/null)
}

# Analyze sudoers configuration for dangerous entries
check_sudoers() {
    log_info "OFFENSIVE" "Analyzing sudoers configuration..."
    
    [[ ! -r /etc/sudoers ]] && {
        log_warn "OFFENSIVE" "Sudoers file not readable (insufficient privileges)"
        return 0
    }
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check for dangerous configurations
        if echo "$line" | grep -qi "NOPASSWD"; then
            log_alert "OFFENSIVE" "Dangerous sudoers rule (no password): $line"
        fi
        
        if echo "$line" | grep -qi "ALL=(ALL)"; then
            log_alert "OFFENSIVE" "Dangerous sudoers rule (full access): $line"
        fi
    done < /etc/sudoers
}

# Run full security audit
run_offensive_scan() {
    log_separator "STARTING SECURITY AUDIT"
    audit_suid_binaries
    audit_world_writable
    check_sudoers
    log_separator "AUDIT COMPLETE"
}

# Export functions for use in run.sh
export -f offensive_init run_offensive_scan audit_suid_binaries audit_world_writable check_sudoers
