#!/usr/bin/env bash
# ChabahRoot M1 — Intégration eBPF
# Compilateur et gestionnaire des programmes eBPF pour le noyau
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly EBPF_TOOLS_DIR="${SCRIPT_DIR}/ebpf"

# Vérifier si les outils eBPF sont disponibles
check_ebpf_tools() {
    require_command bpftool "bpftool" || return 1
    require_command clang "clang" || return 1
    log_success "Outils eBPF disponibles"
}

# Compiler un programme eBPF
compile_ebpf() {
    local source_file="$1" object_file="$2"
    log_info "Compilation du programme eBPF: $source_file"
    
    clang -O2 -g -target bpf -c "$source_file" -o "$object_file" || {
        log_error "Échec de la compilation du programme eBPF"
        return 1
    }
    log_success "Programme eBPF compilé avec succès"
}

# Charger un programme eBPF
load_ebpf() {
    local object_file="$1" program_name="$2"
    log_info "Chargement du programme eBPF: $program_name"
    
    local prog_id
    prog_id=$(bpftool prog load "$object_file" "/sys/fs/bpf/$program_name" type tracepoint 2>&1) || {
        log_error "Échec du chargement du programme eBPF"
        return 1
    }
    
    # Extraire l'ID du programme
    prog_id=$(echo "$prog_id" | grep -oP 'id \K[0-9]+' || echo "$prog_id")
    
    log_success "Programme eBPF chargé avec l'ID: $prog_id"
    echo "$prog_id"
}

# Attacher un programme eBPF à un tracepoint
attach_ebpf() {
    local prog_id="$1" tracepoint="$2"
    log_info "Attachement du programme eBPF au tracepoint: $tracepoint"
    
    bpftool prog attach id "$prog_id" "$tracepoint" || {
        log_error "Échec de l'attachement du programme eBPF au tracepoint"
        return 1
    }
    log_success "Programme eBPF attaché avec succès"
}

# Détacher et décharger un programme eBPF
unload_ebpf() {
    local prog_id="$1"
    log_info "Déchargement du programme eBPF ID: $prog_id"
    
    bpftool prog detach id "$prog_id" 2>/dev/null || true
    rm -f "/sys/fs/bpf/chabah_$prog_id" 2>/dev/null || true
    log_success "Programme eBPF déchargé avec succès"
}

# Vérifier que le programme eBPF event_capture.c existe
verify_ebpf_source() {
    local ebpf_source="$EBPF_TOOLS_DIR/event_capture.c"
    
    if [[ ! -f "$ebpf_source" ]]; then
        log_error "Programme source eBPF non trouvé: $ebpf_source"
        return 1
    fi
    
    log_success "Programme source eBPF détecté"
    echo "$ebpf_source"
}

# Intégration eBPF complète (load/compile/attach with ring buffer)
integrate_ebpf() {
    log_info "Démarrage de l'intégration eBPF avec capture d'événements"
    
    check_ebpf_tools || return 1
    
    # Vérifier que le source existe
    local ebpf_source
    ebpf_source=$(verify_ebpf_source) || return 1
    
    # Compiler les sondes multiples
    local -a tracepoints=(
        "syscalls/sys_enter_execve"
        "syscalls/sys_enter_setuid"
        "syscalls/sys_enter_setgid"
        "syscalls/sys_enter_prctl"
    )
    
    # Compiler le programme event_capture.c
    local ebpf_object="$EBPF_TOOLS_DIR/event_capture.o"
    compile_ebpf "$ebpf_source" "$ebpf_object" || return 1
    
    # Charger et attacher les probes
    local prog_id
    prog_id=$(load_ebpf "$ebpf_object" "chabah_events") || return 1
    
    # Attacher à tous les tracepoints
    for tp in "${tracepoints[@]}"; do
        log_info "Attachement au tracepoint: $tp"
        if ! attach_ebpf "$prog_id" "$tp" 2>/dev/null; then
            log_warn "Impossible d'attacher au tracepoint $tp (peut être non supporté)"
        fi
    done
    
    log_success "Intégration eBPF complétée avec succès (ID: $prog_id)"
    echo "$prog_id"
}

# Nettoyer tous les programmes eBPF ChabahRoot
cleanup_all_ebpf() {
    log_info "Nettoyage de tous les programmes eBPF ChabahRoot"
    
    bpftool prog show 2>/dev/null | grep chabah | while read -r line; do
        local id=$(echo "$line" | awk '{print $1}')
        unload_ebpf "$id" 2>/dev/null || true
    done
    
    log_success "Tous les programmes eBPF ChabahRoot nettoyés"
}

# Programme principal
main() {
    local action="${1:-status}"
    
    case "$action" in
        load)
            integrate_ebpf
            ;;
        cleanup)
            cleanup_all_ebpf
            ;;
        status)
            if bpftool prog show 2>/dev/null | grep -q chabah; then
                log_info "Programmes eBPF ChabahRoot chargés:"
                bpftool prog show 2>/dev/null | grep chabah
            else
                log_info "Aucun programme eBPF ChabahRoot chargé"
            fi
            ;;
        *)
            log_error "Utilisation: $0 {load|cleanup|status}"
            exit 1
            ;;
    esac
}

main "$@"