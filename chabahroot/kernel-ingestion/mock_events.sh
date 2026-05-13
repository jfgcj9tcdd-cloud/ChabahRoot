#!/usr/bin/env bash
# Mock kernel event generator for testing without root
# Generates simulated syscall events matching tracer.sh output format
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

# Generate random-ish but deterministic threat scenario events
generate_threat_scenario() {
    local scenario="$1"
    
    case "$scenario" in
        exec_dropper)
            echo "pid=2101 ppid=1024 uid=1000 gid=1000 ts=$(date +%s) comm=bash argv=/tmp/dropper.sh event_type=1"
            ;;
        setuid_escalation)
            echo "pid=2102 ppid=2101 uid=1000 gid=1000 ts=$(date +%s) comm=sudo argv=setuid(0) event_type=2"
            ;;
        setgid_change)
            echo "pid=2103 ppid=2102 uid=0 gid=0 ts=$(date +%s) comm=bash argv=setgid(4) event_type=3"
            ;;
        prctl_caps)
            echo "pid=2104 ppid=2103 uid=0 gid=0 ts=$(date +%s) comm=exploit argv=prctl(CAP_SYS_ADMIN) event_type=4"
            ;;
    esac
}

main() {
    local mode="${1:-simulate}"
    local arg2="${2:-}"
    local arg3="${3:-}"
    local count=0 scen="" i
    
    case "$mode" in
        simulate)
            log_info "Generating threat scenario events (continuous mode)"
            i=0
            while true; do
                case $((i % 4)) in
                    0) generate_threat_scenario "exec_dropper" ;;
                    1) generate_threat_scenario "setuid_escalation" ;;
                    2) generate_threat_scenario "setgid_change" ;;
                    3) generate_threat_scenario "prctl_caps" ;;
                esac
                ((i++))
                sleep 0.5
            done
            ;;
        single)
            log_info "Generating single threat event"
            generate_threat_scenario "exec_dropper"
            ;;
        scenario)
            scen="${arg2:-exec_dropper}"
            count="${arg3:-1}"
            log_info "Generating scenario: $scen (x$count)"
            for ((i=0; i<count; i++)); do
                generate_threat_scenario "$scen"
                sleep 0.1
            done
            ;;
        *)
            log_info "Usage: $0 {simulate|single|scenario <name> [count]}"
            log_info "Scenarios: exec_dropper, setuid_escalation, setgid_change, prctl_caps"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
