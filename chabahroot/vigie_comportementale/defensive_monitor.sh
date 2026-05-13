#!/usr/bin/env bash
# Ce moniteur reste volontairement grossier et local a la machine.
# Il complete la detection sur syscalls par une vue rapide des processus
# quand le flux vivant est rare ou retarde, sans pretendre fournir une
# preuve plus forte que les evenements issus du traceur noyau.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../socle_commun/rules.conf"
source "$SCRIPT_DIR/../socle_commun/utilitaires.sh"

readonly SEEN_PIDS_FILE="$PROJECT_ROOT/detection/tmp/seen_pids.tmp"

defensive_init() {
    log_info "DEFENSIVE" "Initializing defensive monitor"
    mkdir -p "$(dirname "$SEEN_PIDS_FILE")"
    touch "$SEEN_PIDS_FILE" 2>/dev/null || log_warn "DEFENSIVE" "Could not create PID state file"
    log_info "DEFENSIVE" "Target UID=$TARGET_UID poll=${POLL_INTERVAL}s"
}

detect_uid_escalation() {
    local uid pid ppid cmd msg

    while IFS= read -r uid pid ppid cmd; do
        [[ "$uid" -eq "$TARGET_UID" ]] || continue

        if grep -q "^${pid}$" "$SEEN_PIDS_FILE" 2>/dev/null; then
            continue
        fi

        echo "$pid" >> "$SEEN_PIDS_FILE"
        msg="Elevation detected: PID=$pid PPID=$ppid CMD=$cmd"
        log_alert "DEFENSIVE" "$msg"
        check_suspicious_process "$cmd"
    done < <(ps -eo uid,pid,ppid,comm --no-headers 2>/dev/null)
}

check_suspicious_process() {
    local cmd="$1"
    local suspect

    for suspect in nc ncat netcat bash sh perl python ruby curl wget; do
        if [[ "$cmd" == "$suspect"* ]]; then
            log_alert "DEFENSIVE" "Suspicious process detected: $cmd"
            break
        fi
    done
}

run_defensive_cycle() {
    detect_uid_escalation
}

export -f defensive_init run_defensive_cycle detect_uid_escalation check_suspicious_process
