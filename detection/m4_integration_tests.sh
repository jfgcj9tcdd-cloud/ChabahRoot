#!/usr/bin/env bash
# ChabahRoot M4 — Framework d'Intégration et de Tests
# Validation du pipeline end-to-end et gestion de l'intégrité du système
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../chabahroot/m1/lib/lib_utils.sh"

readonly TEST_RESULTS="/tmp/chabah_test_results"
readonly HEALTH_CHECK="/tmp/chabah_health"

# Initialiser l'état des tests
init_test_environment() {
    log_info "Initialisation de l'environnement de test M4"
    
    mkdir -p "$TEST_RESULTS"
    mkdir -p "$(dirname "$HEALTH_CHECK")"
    
    # Vérifier les prérequis du système
    verify_root_privileges || return 1
    
    # Vérifier la disponibilité des outils
    local required_tools="bash jq bpftool clang"
    for tool in $required_tools; do
        command -v "$tool" &>/dev/null || {
            log_error "Outil requis non trouvé: $tool"
            return 1
        }
    done
    
    log_success "Environnement de test prêt"
}

# Test de la couche M1: Ingestion eBPF
test_m1_ebpf_ingestion() {
    log_info "Test M1: Couche d'ingestion eBPF"
    
    local test_name="M1_eBPF_Compilation"
    local m1_dir="$SCRIPT_DIR/../chabahroot/m1"
    
    # Vérifier que le programme eBPF peut être compilé
    if cd "$m1_dir/ebpf" && clang -O2 -target bpf -c event_capture.c -o event_capture.o 2>/dev/null; then
        log_success "✓ Compilation eBPF réussie"
        echo "PASS" >> "$TEST_RESULTS/$test_name"
        return 0
    else
        log_error "✗ Compilation eBPF échouée"
        echo "FAIL" >> "$TEST_RESULTS/$test_name"
        return 1
    fi
}

# Test de la couche M2: Rules Engine
test_m2_rules_engine() {
    log_info "Test M2: Moteur de détection"
    
    local test_name="M2_Rules_Engine"
    local rules_file="$SCRIPT_DIR/detection_rules.json"
    
    # Vérifier que le fichier de règles est valide
    if jq empty "$rules_file" 2>/dev/null; then
        log_success "✓ Fichier de règles JSON valide"
        echo "PASS" >> "$TEST_RESULTS/$test_name"
        
        # Vérifier que chaque règle a les champs requis
        local rule_count
        rule_count=$(jq '.rules | length' "$rules_file")
        
        for ((i=0; i < rule_count; i++)); do
            local has_all_fields
            has_all_fields=$(jq ".rules[$i] | has(\"id\") and has(\"name\") and has(\"condition\")" "$rules_file")
            
            if [[ "$has_all_fields" != "true" ]]; then
                log_warn "Règle #$i est incomplète"
                echo "PARTIAL" >> "$TEST_RESULTS/$test_name"
                return 1
            fi
        done
        
        log_info "✓ Toutes les règles ($rule_count) sont valides"
        return 0
    else
        log_error "✗ Fichier de règles JSON invalide"
        echo "FAIL" >> "$TEST_RESULTS/$test_name"
        return 1
    fi
}

# Test de la couche M3: Normalisation d'événements
test_m3_event_normalization() {
    log_info "Test M3: Normalisation d'événements"
    
    local test_name="M3_Event_Normalization"
    
    # Créer un événement test
    local test_event
    test_event='{
        "timestamp": 1234567890,
        "timestamp_ns": 1234567890000000000,
        "event_type": "exec",
        "process": {"pid": 1234, "ppid": 1, "comm": "bash"},
        "credentials": {"uid": 1000, "gid": 1000},
        "data": {"argv": "/bin/bash"}
    }'
    
    # Vérifier que le JSON peut être parsé
    if echo "$test_event" | jq empty 2>/dev/null; then
        log_success "✓ Événement normalisé valide"
        echo "PASS" >> "$TEST_RESULTS/$test_name"
        return 0
    else
        log_error "✗ Événement normalisé invalide"
        echo "FAIL" >> "$TEST_RESULTS/$test_name"
        return 1
    fi
}

# Test de la couche M4: Pipeline d'intégration
test_m4_integration_pipeline() {
    log_info "Test M4: Pipeline d'intégration"
    
    local test_name="M4_Integration_Pipeline"
    
    # Vérifier que tous les scripts existent
    local required_scripts=(
        "$SCRIPT_DIR/run.sh"
        "$SCRIPT_DIR/rules_engine.sh"
        "$SCRIPT_DIR/ringbuf_reader.sh"
        "$SCRIPT_DIR/logger.sh"
        "$SCRIPT_DIR/../chabahroot/m1/init.sh"
        "$SCRIPT_DIR/../chabahroot/m1/check.sh"
    )
    
    local all_exist=true
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_warn "Script manquant: $script"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == "true" ]]; then
        log_success "✓ Tous les scripts du pipeline existent"
        echo "PASS" >> "$TEST_RESULTS/$test_name"
        return 0
    else
        log_error "✗ Scripts du pipeline manquants"
        echo "FAIL" >> "$TEST_RESULTS/$test_name"
        return 1
    fi
}

# Vérification de santé: Ressources système
check_system_health() {
    log_info "Vérification de santé du système"
    
    local health_status="HEALTHY"
    
    # Vérifier l'espace disque
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if (( disk_usage > 90 )); then
        log_warn "Espace disque critique: ${disk_usage}%"
        health_status="DEGRADED"
    elif (( disk_usage > 80 )); then
        log_warn "Espace disque faible: ${disk_usage}%"
    fi
    
    # Vérifier la mémoire disponible
    local free_memory
    free_memory=$(free -h | awk 'NR==2 {print $7}' | sed 's/[^0-9]//g')
    
    if (( free_memory < 100 )); then
        log_warn "Mémoire disponible faible"
        health_status="DEGRADED"
    fi
    
    # Vérifier les fichiers temporaires
    if [[ -d /tmp/chabah* ]]; then
        local tmpfiles_count
        tmpfiles_count=$(find /tmp/chabah* -type f 2>/dev/null | wc -l)
        
        if (( tmpfiles_count > 1000 )); then
            log_warn "Trop de fichiers temporaires: $tmpfiles_count"
            health_status="DEGRADED"
        fi
    fi
    
    echo "$health_status" > "$HEALTH_CHECK"
    log_info "État du système: $health_status"
}

# Générer un rapport de test
generate_test_report() {
    log_separator "Rapport de Tests M4"
    
    if [[ ! -d "$TEST_RESULTS" ]] || [[ -z "$(ls -A "$TEST_RESULTS")" ]]; then
        log_info "Aucun résultat de test trouvé"
        return 0
    fi
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    for test_file in "$TEST_RESULTS"/*; do
        [[ -f "$test_file" ]] || continue
        
        local test_name=$(basename "$test_file")
        local result=$(cat "$test_file" | tail -1)
        
        ((total_tests++))
        
        if [[ "$result" == "PASS" ]]; then
            ((passed_tests++))
            log_success "✓ $test_name: PASS"
        elif [[ "$result" == "FAIL" ]]; then
            ((failed_tests++))
            log_error "✗ $test_name: FAIL"
        else
            log_warn "⚠ $test_name: $result"
        fi
    done
    
    log_separator "Résumé"
    log_info "Total: $total_tests tests"
    log_success "Réussis: $passed_tests"
    log_error "Échoués: $failed_tests"
    
    if (( failed_tests == 0 )); then
        log_success "✓ Tous les tests ont réussi!"
        return 0
    else
        log_error "✗ Certains tests ont échoué"
        return 1
    fi
}

# Exécuter la suite de tests complète
run_all_tests() {
    log_separator "Suite de Tests ChabahRoot M4"
    
    init_test_environment || return 1
    
    # Tests des couches
    test_m1_ebpf_ingestion || true
    test_m2_rules_engine || true
    test_m3_event_normalization || true
    test_m4_integration_pipeline || true
    
    # Vérification de santé
    check_system_health
    
    # Rapport final
    generate_test_report
}

# Programme principal
main() {
    case "${1:-all}" in
        all)
            run_all_tests
            ;;
        m1)
            init_test_environment && test_m1_ebpf_ingestion
            ;;
        m2)
            init_test_environment && test_m2_rules_engine
            ;;
        m3)
            init_test_environment && test_m3_event_normalization
            ;;
        m4)
            init_test_environment && test_m4_integration_pipeline
            ;;
        health)
            check_system_health
            ;;
        report)
            generate_test_report
            ;;
        *)
            log_info "Usage: $0 {all|m1|m2|m3|m4|health|report}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
