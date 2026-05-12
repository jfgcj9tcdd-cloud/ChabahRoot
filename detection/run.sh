#!/usr/bin/env bash
# ChabahRoot — Orchestrateur de détection
# Gestion de la surveillance défensive et des audits de sécurité
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/rules.conf" || { echo "[FATAL] Unable to load rules.conf" >&2; exit 1; }
source "$SCRIPT_DIR/logger.sh" || { echo "[FATAL] Unable to load logger.sh" >&2; exit 1; }

DEFENSIVE_PID=""

# Verify all dependencies and scripts exist
check_prerequisites() {
    log_info "SYSTEM" "Checking prerequisites..."
    
    local deps="ps grep awk find"
    for cmd in $deps; do
        command -v "$cmd" &>/dev/null || {
            log_alert "SYSTEM" "Required command not found: $cmd"
            return 1
        }
    done
    
    for script in defensive.sh offensive.sh; do
        [[ -f "$SCRIPT_DIR/$script" ]] || {
            log_alert "SYSTEM" "Required module missing: $script"
            return 1
        }
        chmod +x "$SCRIPT_DIR/$script"
    done
}

# Cleanup handler for signals
cleanup() {
    echo ""
    log_warn "SYSTEM" "Shutdown signal received - stopping detection engine"
    
    # Stop defensive module if running
    if [[ -n "$DEFENSIVE_PID" ]] && kill -0 "$DEFENSIVE_PID" 2>/dev/null; then
        log_info "SYSTEM" "Stopping defensive module (PID=$DEFENSIVE_PID)"
        kill "$DEFENSIVE_PID" 2>/dev/null
        wait "$DEFENSIVE_PID" 2>/dev/null || true
    fi
    
    # Clean up temp files
    rm -f ./tmp/* 2>/dev/null || true
    
    log_separator "SESSION ENDED"
    log_info "SYSTEM" "Detection engine stopped. Log: $LOG_FILE"
    exit 0
}

trap cleanup INT TERM EXIT

# Start defensive module in background
start_defensive_background() {
    log_info "SYSTEM" "Starting defensive monitoring in background"
    
    (
        source "$SCRIPT_DIR/defensive.sh"
        defensive_init
        while true; do
            run_defensive_cycle
            sleep "$POLL_INTERVAL"
        done
    ) &
    
    DEFENSIVE_PID=$!
    log_info "SYSTEM" "Defensive module started (PID=$DEFENSIVE_PID)"
}

# Run offensive security audit (one-shot)
run_offensive_audit() {
    log_info "SYSTEM" "Starting security audit"
    source "$SCRIPT_DIR/offensive.sh"
    offensive_init
    run_offensive_scan
}

# Display usage information
show_help() {
    cat << 'EOF'
ChabahRoot Detection Engine

Usage: ./run.sh [OPTIONS]

OPTIONS:
  --defensive-only    Start only defensive monitoring
  --offensive-only    Run only security audit (one-shot)
  --no-offensive      Start defensive monitoring without audit
  --help              Show this help message

EXAMPLES:
  sudo ./run.sh                      # Full mode (defensive + audit)
  sudo ./run.sh --defensive-only     # Continuous monitoring only
  sudo ./run.sh --offensive-only     # Security audit only
  sudo ./run.sh --no-offensive       # Monitoring without audit

FILES:
  rules.conf          Configuration parameters
  logger.sh           Logging module
  defensive.sh        Defensive monitoring module
  offensive.sh        Offensive audit module
  logs/chabah.log     Main log file

EOF
}

# Main orchestrator
main() {
    local mode="full"
    
    # Parse command-line arguments
    for arg in "$@"; do
        case "$arg" in
            --defensive-only) mode="defensive" ;;
            --offensive-only) mode="offensive" ;;
            --no-offensive) mode="defensive_only" ;;
            --help|-h) show_help; exit 0 ;;
        esac
    done
    
    # Verify prerequisites
    check_prerequisites || exit 1
    
    # Initialize logging
    init_log || exit 1
    
    log_separator "CHABAHROOT DETECTION ENGINE STARTING"
    log_info "SYSTEM" "Mode: $mode | Log: $LOG_FILE"
    
    # Execute based on mode
    case "$mode" in
        defensive)
            start_defensive_background
            run_offensive_audit
            ;;
        offensive)
            run_offensive_audit
            exit 0
            ;;
        defensive_only)
            start_defensive_background
            ;;
        full)
            start_defensive_background
            run_offensive_audit
            ;;
    esac
    
    # Keep defensive module running
    if [[ -n "$DEFENSIVE_PID" ]]; then
        log_info "SYSTEM" "Detection active - press Ctrl+C to stop"
        wait "$DEFENSIVE_PID" 2>/dev/null || true
    fi
}

main "$@"
