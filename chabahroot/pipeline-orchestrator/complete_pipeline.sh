#!/usr/bin/env bash
# ChabahRoot M4 - Orchestrateur complet du pipeline
# Auteur: Équipe Cyber
# Gere le cycle M1 -> M3 -> M2 avec un mode demo sans privileges root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/../shared/logger.sh""
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../shared/rules.conf""

readonly M1_DIR="$PROJECT_ROOT/chabahroot/m1"
readonly M1_INIT="$M1_DIR/m1_complete.sh"
readonly M3_READER="$PROJECT_ROOT/services/m3_transport/ringbuf_reader.sh"
readonly M2_RULES="$PROJECT_ROOT/services/m2_detection/rules_engine.sh"
readonly M4_TESTS="$PROJECT_ROOT/services/m4_integration/m4_integration_tests.sh"

PIPELINE_STATE="${CHABAH_PIPELINE_STATE:-/tmp/chabah_pipeline_state}"
EVENT_PIPE=""

M1_PID=""
M2_PID=""
M3_PID=""
PIPELINE_STOPPED=0

init_pipeline() {
    log_info "PIPELINE" "Initialisation du pipeline complet"

    resolve_pipeline_state
    mkdir -p "$PIPELINE_STATE"
    chmod +x "$M1_INIT" "$M2_RULES" "$M3_READER" "$M4_TESTS" 2>/dev/null || true

    rm -f "$EVENT_PIPE"
    mkfifo "$EVENT_PIPE"

    log_success "PIPELINE" "Environnement pipeline pret"
}

verify_pipeline_prerequisites() {
    log_info "PIPELINE" "Verification des prerequis"

    local required_scripts=("$M3_READER" "$M2_RULES")
    local required_cmds=(bash jq mkfifo)
    local item

    for item in "${required_scripts[@]}"; do
        if [[ ! -f "$item" ]]; then
            log_error "PIPELINE" "Script manquant: $item"
            return 1
        fi
    done

    for item in "${required_cmds[@]}"; do
        if ! command -v "$item" >/dev/null 2>&1; then
            log_error "PIPELINE" "Commande requise absente: $item"
            return 1
        fi
    done

    if [[ "${CHABAH_SKIP_M1:-0}" != "1" ]] && [[ $EUID -ne 0 ]]; then
        log_error "PIPELINE" "Privileges root requis pour M1"
        log_info "PIPELINE" "Utiliser CHABAH_SKIP_M1=1 pour un mode demo"
        return 1
    fi

    log_success "PIPELINE" "Prerequis valides"
}

resolve_pipeline_state() {
    local fallback_state test_file

    fallback_state="$PROJECT_ROOT/detection/tmp/chabah_pipeline_state"

    if mkdir -p "$PIPELINE_STATE" 2>/dev/null; then
        test_file="$PIPELINE_STATE/.write_test"
        if touch "$test_file" >/dev/null 2>&1; then
            rm -f "$test_file"
            EVENT_PIPE="$PIPELINE_STATE/event_stream.pipe"
            return 0
        fi
    fi

    PIPELINE_STATE="$fallback_state"
    mkdir -p "$PIPELINE_STATE"
    EVENT_PIPE="$PIPELINE_STATE/event_stream.pipe"
    log_warn "PIPELINE" "Fallback vers un etat local: $PIPELINE_STATE"
}

start_m1_ingestion() {
    if [[ "${CHABAH_SKIP_M1:-0}" == "1" ]]; then
        log_warn "PIPELINE" "M1 ignore en mode demo"
        return 0
    fi

    log_info "PIPELINE" "Demarrage de M1"

    bash "$M1_INIT" start > "$PIPELINE_STATE/m1.log" 2>&1 &
    M1_PID=$!
    echo "$M1_PID" > "$PIPELINE_STATE/m1.pid"
    sleep 2

    if kill -0 "$M1_PID" 2>/dev/null; then
        log_success "PIPELINE" "M1 demarre (PID=$M1_PID)"
        return 0
    fi

    log_error "PIPELINE" "Echec du demarrage de M1"
    return 1
}

start_m2_analysis() {
    log_info "PIPELINE" "Demarrage de M2"

    bash "$M2_RULES" < "$EVENT_PIPE" > "$PIPELINE_STATE/m2.log" 2>&1 &
    M2_PID=$!
    echo "$M2_PID" > "$PIPELINE_STATE/m2.pid"
    sleep 1

    if kill -0 "$M2_PID" 2>/dev/null; then
        log_success "PIPELINE" "M2 demarre (PID=$M2_PID)"
        return 0
    fi

    log_error "PIPELINE" "Echec du demarrage de M2"
    return 1
}

start_m3_transport() {
    log_info "PIPELINE" "Demarrage de M3"

    bash "$M3_READER" > "$EVENT_PIPE" 2> "$PIPELINE_STATE/m3.log" &
    M3_PID=$!
    echo "$M3_PID" > "$PIPELINE_STATE/m3.pid"
    sleep 1

    if kill -0 "$M3_PID" 2>/dev/null; then
        log_success "PIPELINE" "M3 demarre (PID=$M3_PID)"
        return 0
    fi

    if [[ "${CHABAH_SKIP_M1:-0}" == "1" ]]; then
        if wait "$M3_PID"; then
            log_success "PIPELINE" "M3 a termine le flux demo"
            M3_PID=""
            return 0
        fi
    fi

    log_error "PIPELINE" "Echec du demarrage de M3"
    return 1
}

show_status() {
    log_separator "Etat du pipeline ChabahRoot"

    if [[ "${CHABAH_SKIP_M1:-0}" == "1" ]]; then
        log_warn "STATUS" "M1: ignore (mode demo)"
    elif [[ -n "$M1_PID" ]] && kill -0 "$M1_PID" 2>/dev/null; then
        log_info "STATUS" "M1: actif (PID=$M1_PID)"
    else
        log_warn "STATUS" "M1: inactif"
    fi

    if [[ -n "$M3_PID" ]] && kill -0 "$M3_PID" 2>/dev/null; then
        log_info "STATUS" "M3: actif (PID=$M3_PID)"
    else
        log_warn "STATUS" "M3: inactif"
    fi

    if [[ -n "$M2_PID" ]] && kill -0 "$M2_PID" 2>/dev/null; then
        log_info "STATUS" "M2: actif (PID=$M2_PID)"
    else
        log_warn "STATUS" "M2: inactif"
    fi
}

stop_pipeline() {
    [[ "$PIPELINE_STOPPED" -eq 1 ]] && return 0
    PIPELINE_STOPPED=1

    log_info "PIPELINE" "Arret du pipeline"

    if [[ -n "$M3_PID" ]] && kill -0 "$M3_PID" 2>/dev/null; then
        kill "$M3_PID" 2>/dev/null || true
        wait "$M3_PID" 2>/dev/null || true
    fi

    if [[ -n "$M2_PID" ]] && kill -0 "$M2_PID" 2>/dev/null; then
        kill "$M2_PID" 2>/dev/null || true
        wait "$M2_PID" 2>/dev/null || true
    fi

    if [[ -n "$M1_PID" ]] && kill -0 "$M1_PID" 2>/dev/null; then
        bash "$M1_INIT" stop >/dev/null 2>&1 || true
        kill "$M1_PID" 2>/dev/null || true
        wait "$M1_PID" 2>/dev/null || true
    fi

    rm -f "$EVENT_PIPE"
    log_success "PIPELINE" "Pipeline arrete"
}

cleanup() {
    log_warn "PIPELINE" "Signal d'arret recu"
    stop_pipeline
    exit 0
}

run_pipeline() {
    trap cleanup INT TERM

    log_separator "Demarrage du pipeline ChabahRoot (M1->M3->M2)"
    init_pipeline
    verify_pipeline_prerequisites
    start_m1_ingestion
    start_m2_analysis
    start_m3_transport
    show_status

    if [[ "${CHABAH_SKIP_M1:-0}" == "1" ]]; then
        if [[ -n "$M2_PID" ]]; then
            wait "$M2_PID" 2>/dev/null || true
        fi
        stop_pipeline
        return 0
    fi

    while true; do
        sleep 2

        if [[ -n "$M3_PID" ]] && ! kill -0 "$M3_PID" 2>/dev/null; then
            log_error "PIPELINE" "M3 est tombe"
            break
        fi

        if [[ -n "$M2_PID" ]] && ! kill -0 "$M2_PID" 2>/dev/null; then
            log_error "PIPELINE" "M2 est tombe"
            break
        fi

        if [[ "${CHABAH_SKIP_M1:-0}" != "1" ]] && [[ -n "$M1_PID" ]] && ! kill -0 "$M1_PID" 2>/dev/null; then
            log_error "PIPELINE" "M1 est tombe"
            break
        fi

        if [[ "${CHABAH_SKIP_M1:-0}" == "1" ]] && [[ -n "${CHABAH_EVENT_SOURCE:-}" ]] && [[ ! -f "$CHABAH_EVENT_SOURCE" ]]; then
            log_error "PIPELINE" "Source demo absente: $CHABAH_EVENT_SOURCE"
            break
        fi
    done

    stop_pipeline
}

main() {
    case "${1:-run}" in
        run)
            run_pipeline
            ;;
        demo)
            export CHABAH_SKIP_M1=1
            export CHABAH_EVENT_SOURCE="${CHABAH_EVENT_SOURCE:-$PROJECT_ROOT/examples/sample_events.ndjson}"
            run_pipeline
            ;;
        start)
            nohup "$0" run >/dev/null 2>&1 &
            log_info "PIPELINE" "Pipeline lance en arriere-plan (PID=$!)"
            ;;
        stop)
            stop_pipeline
            ;;
        status)
            show_status
            ;;
        test)
            bash "$M4_TESTS" all
            ;;
        *)
            log_info "USAGE" "$0 {run|demo|start|stop|status|test}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
