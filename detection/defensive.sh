#!/usr/bin/env bash
# ChabahRoot — Module de détection défensive
# Surveillance continue des escalades de privilèges et processus suspects
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/rules.conf" || exit 1
source "$SCRIPT_DIR/logger.sh" || exit 1

readonly SEEN_PIDS_FILE="./tmp/seen_pids.tmp"

# Initialize defensive module
defensive_init() {
    log_info "DEFENSIVE" "Initializing defensive monitoring module"
    mkdir -p ./tmp
    touch "$SEEN_PIDS_FILE" 2>/dev/null || {
        log_warn "DEFENSIVE" "Unable to create PID tracking file"
    }
    log_info "DEFENSIVE" "Target UID: $TARGET_UID (root) | Poll interval: ${POLL_INTERVAL}s"
}

# Scan for privilege escalation (UID=0) processes
detect_uid_escalation() {
    log_debug "DEFENSIVE" "Scanning for root privilege escalation..."
    
    while IFS= read -r uid pid ppid cmd; do
        # Skip if UID doesn't match target
        [[ "$uid" -eq "$TARGET_UID" ]] || continue
        
        # Skip already-seen PIDs to prevent spam
        if grep -q "^${pid}$" "$SEEN_PIDS_FILE" 2>/dev/null; then
            continue
        fi
        
        echo "$pid" >> "$SEEN_PIDS_FILE"
        
        local msg="ROOT escalation: PID=$pid PPID=$ppid CMD=$cmd"
        log_alert "DEFENSIVE" "$msg"
        
        # Check for suspicious process names
        check_suspicious_process "$cmd"
        
    done < <(ps -eo uid,pid,ppid,comm --no-headers 2>/dev/null)
}

# Check if process name is in suspicious list
check_suspicious_process() {
    local cmd="$1"
    local suspicious="nc ncat netcat bash sh perl python ruby"
    
    for suspect in $suspicious; do
        if [[ "$cmd" == "$suspect"* ]]; then
            log_alert "DEFENSIVE" "Suspicious process detected: $cmd"
            break
        fi
    done
}

# Run one defensive cycle
run_defensive_cycle() {
    detect_uid_escalation
}

# Export functions for use in run.sh
export -f defensive_init run_defensive_cycle detect_uid_escalation check_suspicious_process
