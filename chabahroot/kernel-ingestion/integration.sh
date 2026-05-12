#!/usr/bin/env bash
# ChabahRoot - Integration eBPF (Kernel Ingestion M1)
# Auteur: MOUSAAB EL HARMALI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils".sh"

readonly EBPF_TOOLS_DIR="${SCRIPT_DIR}/ebpf"

check_ebpf_tools() {
    require_command bpftool "bpftool" || return 1
    require_command clang "clang" || return 1
    log_success "Outils eBPF disponibles"
}

compile_ebpf() {
    local source_file="$1" object_file="$2"
    log_info "Compilation du programme eBPF: $source_file"
    
    clang -O2 -g -target bpf -c "$source_file" -o "$object_file" || {
        log_error "Echec de la compilation du programme eBPF"
        return 1
    }
    log_success "Programme eBPF compile avec succes"
}

load_ebpf() {
    local object_file="$1" program_name="$2"
    log_info "Chargement du programme eBPF: $program_name"
    
    local prog_id
    prog_id=$(bpftool prog load "$object_file" "/sys/fs/bpf/$program_name" type tracepoint 2>&1) || {
        log_error "Echec du chargement du programme eBPF"
        return 1
    }
    
    prog_id=$(echo "$prog_id" | grep -oP 'id \K[0-9]+' || echo "$prog_id")
    
    log_success "Programme eBPF charge avec l'ID: $prog_id"
    echo "$prog_id"
}

attach_ebpf() {
    local prog_id="$1" tracepoint="$2"
    log_info "Attachement du programme eBPF au tracepoint: $tracepoint"
    
    bpftool prog attach id "$prog_id" "$tracepoint" || {
        log_error "Echec de l'attachement du programme eBPF au tracepoint"
        return 1
    }
    log_success "Programme eBPF attache avec succes"
}

unload_ebpf() {
    local prog_id="$1"
    log_info "Dechargement du programme eBPF ID: $prog_id"
    
    bpftool prog detach id "$prog_id" 2>/dev/null || true
    rm -f "/sys/fs/bpf/chabah_$prog_id" 2>/dev/null || true
    log_success "Programme eBPF dechargé avec succes"
}

verify_ebpf_source() {
    local ebpf_source="$EBPF_TOOLS_DIR/event_capture.c"
    
    if [[ ! -f "$ebpf_source" ]]; then
        log_error "Programme source eBPF non trouve: $ebpf_source"
        return 1
    fi
    
    log_success "Programme source eBPF detecte"
    echo "$ebpf_source"
}

integrate_ebpf() {
    log_info "Demarrage de l'integration eBPF avec capture d'evenements"
    
    check_ebpf_tools || return 1
    
    local ebpf_source
    ebpf_source=$(verify_ebpf_source) || return 1
    local -a tracepoints=(
        "syscalls/sys_enter_execve"
        "syscalls/sys_enter_setuid"
        "syscalls/sys_enter_setgid"
        "syscalls/sys_enter_prctl"
    )
    
    local ebpf_object="$EBPF_TOOLS_DIR/event_capture.o"
    compile_ebpf "$ebpf_source" "$ebpf_object" || return 1
    local prog_id
    prog_id=$(load_ebpf "$ebpf_object" "chabah_events") || return 1
    
    for tp in "${tracepoints[@]}"; do
        log_info "Attachement au tracepoint: $tp"
        if ! attach_ebpf "$prog_id" "$tp" 2>/dev/null; then
            log_warn "Impossible d'attacher au tracepoint $tp (peut etre non supporte)"
        fi
    done
    
    log_success "Integration eBPF completee avec succes (ID: $prog_id)"
    echo "$prog_id"
}

cleanup_all_ebpf() {
    log_info "Nettoyage de tous les programmes eBPF ChabahRoot"
    
    bpftool prog show 2>/dev/null | grep chabah | while read -r line; do
        local id=$(echo "$line" | awk '{print $1}')
        unload_ebpf "$id" 2>/dev/null || true
    done
    
    log_success "Tous les programmes eBPF ChabahRoot nettoyes"
}

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
                log_info "Programmes eBPF ChabahRoot charges:"
                bpftool prog show 2>/dev/null | grep chabah
            else
                log_info "Aucun programme eBPF ChabahRoot charge"
            fi
            ;;
        *)
            log_error "Utilisation: $0 {load|cleanup|status}"
            exit 1
            ;;
    esac
}

main "$@"