#!/usr/bin/env bash
# This audit stays read only and host aware.
# It is useful as a side channel for hardening drift, but it is not part
# of the live syscall stream and should be treated as contextual signal
# rather than confirmation that an attack is in progress.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../socle_commun/rules.conf"
source "$SCRIPT_DIR/../socle_commun/utilitaires.sh"

offensive_init() {
    log_info "OFFENSIVE" "Initializing offensive audit"
    log_warn "OFFENSIVE" "Audit mode reads host state only"
}

audit_suid_binaries() {
    local whitelist="sudo su passwd ping mount umount newgrp chsh chfn"
    local binary bin_name

    log_info "OFFENSIVE" "Scanning SUID binaries"

    while IFS= read -r binary; do
        bin_name="$(basename "$binary")"

        if [[ ! " $whitelist " =~ [[:space:]]$bin_name[[:space:]] ]]; then
            log_alert "OFFENSIVE" "Non standard SUID binary: $binary"
        else
            log_debug "OFFENSIVE" "Known SUID binary: $binary"
        fi
    done < <(find /usr /bin /sbin /tmp /opt -perm -4000 -type f 2>/dev/null)
}

audit_world_writable() {
    local file

    log_info "OFFENSIVE" "Scanning world writable files in critical paths"

    while IFS= read -r file; do
        log_alert "OFFENSIVE" "World writable file in critical path: $file"
    done < <(find /etc /usr/bin /usr/sbin /bin /sbin -perm -0002 -type f 2>/dev/null)
}

check_sudoers() {
    local line

    log_info "OFFENSIVE" "Scanning sudoers configuration"

    [[ -r /etc/sudoers ]] || {
        log_warn "OFFENSIVE" "sudoers is not readable"
        return 0
    }

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if grep -qi "NOPASSWD" <<< "$line"; then
            log_alert "OFFENSIVE" "Risky sudoers rule: $line"
        fi

        if grep -qi "ALL=(ALL)" <<< "$line"; then
            log_alert "OFFENSIVE" "Broad sudoers rule: $line"
        fi
    done < /etc/sudoers
}

run_offensive_scan() {
    log_separator "Starting offensive audit"
    audit_suid_binaries
    audit_world_writable
    check_sudoers
    log_separator "Offensive audit complete"
}

main() {
    offensive_init
    run_offensive_scan
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
