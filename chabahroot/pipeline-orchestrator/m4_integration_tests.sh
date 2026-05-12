#!/usr/bin/env bash
# ChabahRoot M4 - Framework de verification et de tests
# Auteur: Équipe Cyber
# Valide le pipeline demo, les regles et la structure des scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/../shared/logger.sh""

readonly TEST_RESULTS="/tmp/chabah_test_results"
readonly SAMPLE_FILE="$PROJECT_ROOT/examples/sample_events.ndjson"
readonly ALERTS_FILE="/tmp/chabah_detection_state/alerts.ndjson"

record_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"

    mkdir -p "$TEST_RESULTS"
    printf '%s\n' "$result${details:+|$details}" > "$TEST_RESULTS/$test_name"
}

init_test_environment() {
    log_info "TEST" "Initialisation de l'environnement de test"
    mkdir -p "$TEST_RESULTS"
    rm -f "$TEST_RESULTS"/*
}

test_shell_syntax() {
    local test_name="syntaxe_scripts"

    if bash -n \
        "$PROJECT_ROOT/detection/run.sh" \
        "$PROJECT_ROOT/services/m4_integration/complete_pipeline.sh" \
        "$PROJECT_ROOT/services/m3_transport/ringbuf_reader.sh" \
        "$PROJECT_ROOT/services/m2_detection/rules_engine.sh" \
        "$PROJECT_ROOT/detection/defensive.sh" \
        "$PROJECT_ROOT/detection/offensive.sh" \
        "$PROJECT_ROOT/services/shared/logger.sh" \
        "$PROJECT_ROOT/chabahroot/m1/m1_complete.sh" \
        "$PROJECT_ROOT/chabahroot/m1/ebpf_integration.sh" \
        "$PROJECT_ROOT/chabahroot/m1/check.sh" \
        "$PROJECT_ROOT/chabahroot/m1/init.sh" \
        "$PROJECT_ROOT/chabahroot/m1/cleanup.sh" \
        "$PROJECT_ROOT/detection.sh"; then
        log_success "TEST" "Syntaxe shell valide"
        record_result "$test_name" "PASS"
        return 0
    fi

    log_error "TEST" "Erreur de syntaxe shell detectee"
    record_result "$test_name" "FAIL"
    return 1
}

test_rules_json() {
    local test_name="regles_json"

    if jq empty "$PROJECT_ROOT/services/m2_detection/detection_rules.json" >/dev/null 2>&1; then
        log_success "TEST" "JSON des regles valide"
        record_result "$test_name" "PASS"
        return 0
    fi

    log_error "TEST" "JSON des regles invalide"
    record_result "$test_name" "FAIL"
    return 1
}

test_m3_normalization() {
    local test_name="m3_normalisation"
    local output_file="/tmp/chabah_m3_output.ndjson"

    if [[ ! -f "$SAMPLE_FILE" ]]; then
        log_error "TEST" "Fichier sample absent: $SAMPLE_FILE"
        record_result "$test_name" "FAIL"
        return 1
    fi

    bash "$PROJECT_ROOT/services/m3_transport/ringbuf_reader.sh" --sample > "$output_file"

    if [[ ! -s "$output_file" ]]; then
        log_error "TEST" "Aucune sortie M3 generee"
        record_result "$test_name" "FAIL"
        return 1
    fi

    if jq -s 'all(.[]; has("event_type") and has("process") and has("credentials") and has("data"))' "$output_file" | grep -q true; then
        log_success "TEST" "Normalisation M3 valide"
        record_result "$test_name" "PASS"
        return 0
    fi

    log_error "TEST" "Sortie M3 invalide"
    record_result "$test_name" "FAIL"
    return 1
}

test_m2_rule_engine() {
    local test_name="m2_moteur_regles"
    local normalized_file="/tmp/chabah_m3_output.ndjson"

    rm -rf /tmp/chabah_detection_state
    bash "$PROJECT_ROOT/services/m3_transport/ringbuf_reader.sh" --sample > "$normalized_file"
    bash "$PROJECT_ROOT/services/m2_detection/rules_engine.sh" < "$normalized_file" >/tmp/chabah_m2_stdout.log 2>/tmp/chabah_m2_stderr.log

    if [[ -s "$ALERTS_FILE" ]]; then
        log_success "TEST" "M2 a genere des alertes"
        record_result "$test_name" "PASS"
        return 0
    fi

    log_error "TEST" "M2 n'a genere aucune alerte"
    record_result "$test_name" "FAIL"
    return 1
}

test_project_structure() {
    local test_name="structure_projet"
    local required_paths=(
        "$PROJECT_ROOT/README.md"
        "$PROJECT_ROOT/services/m4_integration/complete_pipeline.sh"
        "$PROJECT_ROOT/services/m3_transport/ringbuf_reader.sh"
        "$PROJECT_ROOT/services/m2_detection/rules_engine.sh"
        "$PROJECT_ROOT/services/shared/logger.sh"
        "$PROJECT_ROOT/chabahroot/m1/m1_complete.sh"
        "$PROJECT_ROOT/examples/sample_events.ndjson"
        "$PROJECT_ROOT/reports/latex/chabahroot_report.tex"
    )
    local path

    for path in "${required_paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            log_error "TEST" "Element structurel manquant: $path"
            record_result "$test_name" "FAIL"
            return 1
        fi
    done

    log_success "TEST" "Structure projet verifiee"
    record_result "$test_name" "PASS"
}

test_m1_source_presence() {
    local test_name="m1_sources"
    local source_file="$PROJECT_ROOT/chabahroot/m1/ebpf/event_capture.c"

    if [[ ! -f "$source_file" ]]; then
        log_error "TEST" "Source eBPF absente"
        record_result "$test_name" "FAIL"
        return 1
    fi

    if command -v clang >/dev/null 2>&1; then
        log_info "TEST" "clang detecte, verification de presence source OK"
        record_result "$test_name" "PASS"
        return 0
    fi

    log_warn "TEST" "clang absent, verification limitee a la presence du source"
    record_result "$test_name" "SKIP" "clang absent"
    return 0
}

generate_test_report() {
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    local test_file result line test_name

    log_separator "Rapport de verification M4"

    if [[ ! -d "$TEST_RESULTS" ]] || [[ -z "$(ls -A "$TEST_RESULTS" 2>/dev/null)" ]]; then
        log_info "TEST" "Aucun resultat de test trouve"
        return 0
    fi

    for test_file in "$TEST_RESULTS"/*; do
        [[ -f "$test_file" ]] || continue
        test_name="$(basename "$test_file")"
        line="$(tail -n 1 "$test_file")"
        result="${line%%|*}"
        ((total_tests+=1))

        case "$result" in
            PASS)
                ((passed_tests+=1))
                log_success "TEST" "$test_name: PASS"
                ;;
            FAIL)
                ((failed_tests+=1))
                log_error "TEST" "$test_name: FAIL"
                ;;
            SKIP)
                ((skipped_tests+=1))
                log_warn "TEST" "$test_name: SKIP"
                ;;
            *)
                log_warn "TEST" "$test_name: $line"
                ;;
        esac
    done

    log_info "TEST" "Total: $total_tests"
    log_info "TEST" "Pass: $passed_tests"
    log_info "TEST" "Fail: $failed_tests"
    log_info "TEST" "Skip: $skipped_tests"

    if (( failed_tests > 0 )); then
        return 1
    fi
}

run_all_tests() {
    init_test_environment
    test_shell_syntax || true
    test_rules_json || true
    test_m3_normalization || true
    test_m2_rule_engine || true
    test_m1_source_presence || true
    test_project_structure || true
    generate_test_report
}

main() {
    case "${1:-all}" in
        all)
            run_all_tests
            ;;
        report)
            generate_test_report
            ;;
        m2)
            init_test_environment
            test_rules_json
            test_m2_rule_engine
            ;;
        m3)
            init_test_environment
            test_m3_normalization
            ;;
        *)
            log_info "TEST" "Usage: $0 {all|m2|m3|report}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
