#!/usr/bin/env bash
# Cette etape relie le flux normalise au moteur comportemental.
# Elle accepte un relais tracefs vivant ou un corpus hors ligne afin que
# les essais puissent couvrir le pipeline sans forcer une capture noyau.
# L audit optionnel reste separe pour ne pas brouiller les observations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../socle_commun/rules.conf"
source "$SCRIPT_DIR/../socle_commun/utilitaires.sh"

readonly DEFAULT_EVENT_SOURCE="/tmp/chabah_kernel_events.pipe"
readonly NORMALIZER="$SCRIPT_DIR/../chaines_d_ecoute/ringbuf_reader.sh"
readonly RULES_ENGINE="$SCRIPT_DIR/../vigie_comportementale/rules_engine.sh"
readonly OFFENSIVE_AUDIT="$SCRIPT_DIR/../vigie_comportementale/offensive_audit.sh"
readonly DEFENSIVE_MONITOR="$SCRIPT_DIR/../vigie_comportementale/defensive_monitor.sh"

DEFENSIVE_PID=""

check_prerequisites() {
    local cmd

    for cmd in bash jq timeout ps find; do
        command -v "$cmd" >/dev/null 2>&1 || {
            log_alert "SYSTEM" "Missing required command: $cmd"
            return 1
        }
    done

    [[ -f "$NORMALIZER" ]] || {
        log_alert "SYSTEM" "Missing module: $NORMALIZER"
        return 1
    }

    [[ -f "$RULES_ENGINE" ]] || {
        log_alert "SYSTEM" "Missing module: $RULES_ENGINE"
        return 1
    }
}

cleanup() {
    if [[ -n "$DEFENSIVE_PID" ]] && kill -0 "$DEFENSIVE_PID" 2>/dev/null; then
        kill "$DEFENSIVE_PID" 2>/dev/null || true
        wait "$DEFENSIVE_PID" 2>/dev/null || true
    fi
}

start_defensive_background() {
    (
        source "$DEFENSIVE_MONITOR"
        defensive_init

        while true; do
            run_defensive_cycle
            sleep "$POLL_INTERVAL"
        done
    ) &

    DEFENSIVE_PID="$!"
    log_info "SYSTEM" "Defensive monitor started with PID=$DEFENSIVE_PID"
}

run_offensive_audit() {
    log_info "SYSTEM" "Running offensive audit"
    bash "$OFFENSIVE_AUDIT"
}

resolve_input_mode() {
    local requested_mode="$1"
    local requested_source="$2"

    if [[ "$requested_mode" == "sample" ]]; then
        printf -- '--sample\n'
        return 0
    fi

    if [[ "$requested_mode" == "stdin" ]]; then
        printf -- '--stdin\n'
        return 0
    fi

    if [[ -n "$requested_source" ]]; then
        printf -- '--input\n%s\n' "$requested_source"
        return 0
    fi

    if [[ -n "${CHABAH_EVENT_SOURCE:-}" ]]; then
        printf -- '--input\n%s\n' "$CHABAH_EVENT_SOURCE"
        return 0
    fi

    if [[ -e "$DEFAULT_EVENT_SOURCE" ]]; then
        printf -- '--input\n%s\n' "$DEFAULT_EVENT_SOURCE"
        return 0
    fi

    printf -- '--sample\n'
}

run_pipeline() {
    local input_mode="$1"
    local input_source="$2"
    local -a normalizer_args

    mapfile -t normalizer_args < <(resolve_input_mode "$input_mode" "$input_source")
    log_info "SYSTEM" "Launching analysis pipeline with ${normalizer_args[*]}"

    bash "$NORMALIZER" "${normalizer_args[@]}" | bash "$RULES_ENGINE"
}

show_help() {
    cat <<'EOF'
Usage: run_detection.sh [--sample|--stdin|--input <file>] [--pipeline-only|--audit-only]

The default mode prefers CHABAH_EVENT_SOURCE, then /tmp/chabah_kernel_events.pipe,
then falls back to the sample corpus.
EOF
}

main() {
    local input_mode="auto"
    local input_source=""
    local execution_mode="full"
    local arg

    trap cleanup EXIT INT TERM
    check_prerequisites
    init_log

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --sample)
                input_mode="sample"
                shift
                ;;
            --stdin)
                input_mode="stdin"
                shift
                ;;
            --input)
                input_source="${2:-}"
                [[ -n "$input_source" ]] || {
                    log_alert "SYSTEM" "Missing file after --input"
                    exit 1
                }
                shift 2
                ;;
            --pipeline-only)
                execution_mode="pipeline_only"
                shift
                ;;
            --audit-only)
                execution_mode="audit_only"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_alert "SYSTEM" "Unknown argument: $arg"
                show_help
                exit 1
                ;;
        esac
    done

    log_separator "Starting analysis stage"

    case "$execution_mode" in
        audit_only)
            run_offensive_audit
            ;;
        pipeline_only)
            run_pipeline "$input_mode" "$input_source"
            ;;
        full)
            start_defensive_background
            run_offensive_audit
            run_pipeline "$input_mode" "$input_source"
            ;;
    esac
}

main "$@"
