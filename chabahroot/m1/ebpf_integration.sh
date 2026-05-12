#!/bin/bash
# Mousaab El harmali
# Integration eBPF
# Chargeur eBPF pour traçage ameliore du noyau

set -euo pipefail

# Charger les bibliotheques d'utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh" 2>/dev/null || {
    # Fonctions minimales si les bibliotheques ne sont pas disponibles
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_success() { echo "[OK] $1"; }
}

# Configuration
EBPF_TOOLS_DIR="${SCRIPT_DIR}/ebpf"
LOG_FILE="/var/log/chabahroot/ebpf.log"

# Fonctions de journalisation
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2 | tee -a "$LOG_FILE" >&2; }

# Verifier si les outils eBPF sont disponibles
check_ebpf_tools() {
    if ! command -v bpftool &> /dev/null; then
        log_error "bpftool non trouve. Installez avec: apt-get install bpftool"
        return 1
    fi

    if ! command -v clang &> /dev/null; then
        log_error "clang non trouve. Installez avec: apt-get install clang"
        return 1
    fi

    log_info "Outils eBPF disponibles"
    return 0
}

# Compiler un programme eBPF
compile_ebpf() {
    local source_file="$1"
    local object_file="$2"

    log_info "Compilation du programme eBPF: $source_file"

    if ! clang -O2 -g -target bpf -c "$source_file" -o "$object_file"; then
        log_error "echec de la compilation du programme eBPF"
        return 1
    fi

    log_info "Programme eBPF compile avec succes"
}

# Charger un programme eBPF
load_ebpf() {
    local object_file="$1"
    local program_name="$2"

    log_info "Chargement du programme eBPF: $program_name"

    # Charger le programme et obtenir son ID
    local prog_id
    if ! prog_id=$(bpftool prog load "$object_file" "/sys/fs/bpf/$program_name" type tracepoint); then
        log_error "echec du chargement du programme eBPF"
        return 1
    fi

    # Extraire l'ID du programme de la sortie
    prog_id=$(echo "$prog_id" | grep -o 'id [0-9]*' | cut -d' ' -f2)

    log_info "Programme eBPF charge avec l'ID: $prog_id"
    echo "$prog_id"
}

# Attacher un programme eBPF à un tracepoint
attach_ebpf() {
    local prog_id="$1"
    local tracepoint="$2"

    log_info "Attachement du programme eBPF au tracepoint: $tracepoint"

    if ! bpftool prog attach id "$prog_id" "$tracepoint"; then
        log_error "echec de l'attachement du programme eBPF au tracepoint"
        return 1
    fi

    log_info "Programme eBPF attache avec succes"
}

# Decharger un programme eBPF
unload_ebpf() {
    local prog_id="$1"

    log_info "Dechargement du programme eBPF ID: $prog_id"

    if ! bpftool prog detach id "$prog_id"; then
        log_error "echec du detachement du programme eBPF"
        return 1
    fi

    # Supprimer du systeme de fichiers BPF
    rm -f "/sys/fs/bpf/chabah_$prog_id"

    log_info "Programme eBPF decharge avec succes"
}

# Programme eBPF simple pour filtrage des appels systeme
create_simple_ebpf_program() {
    local ebpf_source="$EBPF_TOOLS_DIR/simple_filter.c"

    mkdir -p "$EBPF_TOOLS_DIR"

    cat > "$ebpf_source" << 'EOF'
// Programme eBPF simple pour filtrage des appels systeme ChabahRoot
#include <linux/bpf.h>
#include <linux/tracepoint.h>

SEC("tracepoint/syscalls/sys_enter_execve")
int trace_execve_filter(struct trace_event_raw_sys_enter *ctx) {
    char comm[16];
    bpf_get_current_comm(&comm, sizeof(comm));

    // Ignorer les threads noyau (noms commençant par '[')
    if (comm[0] == '[') {
        return 0;  // Ne pas tracer
    }

    // Autoriser le traçage des autres processus
    return 1;
}

char _license[] SEC("license") = "GPL";
EOF

    log_info "Programme de filtre eBPF simple cree"
    echo "$ebpf_source"
}

# Fonction principale d'integration eBPF
integrate_ebpf() {
    local use_ebpf="${1:-false}"

    if [[ "$use_ebpf" != "true" ]]; then
        log_info "Integration eBPF desactivee"
        return 0
    fi

    log_info "Demarrage de l'integration eBPF"

    # Verifier les prerequis
    if ! check_ebpf_tools; then
        log_error "Outils eBPF non disponibles, retour au traçage standard"
        return 1
    fi

    # Creer un programme eBPF
    local ebpf_source
    if ! ebpf_source=$(create_simple_ebpf_program); then
        log_error "echec de la creation du programme eBPF"
        return 1
    fi

    # Compiler le programme eBPF
    local ebpf_object="$EBPF_TOOLS_DIR/simple_filter.o"
    if ! compile_ebpf "$ebpf_source" "$ebpf_object"; then
        return 1
    fi

    # Charger le programme eBPF
    local prog_id
    if ! prog_id=$(load_ebpf "$ebpf_object" "chabah_filter"); then
        return 1
    fi

    # Attacher au tracepoint
    if ! attach_ebpf "$prog_id" "syscalls/sys_enter_execve"; then
        unload_ebpf "$prog_id" 2>/dev/null || true
        return 1
    fi

    log_info "Integration eBPF completee avec succes"
    echo "$prog_id"  # Retourner l'ID du programme pour nettoyage
}

# Nettoyer les programmes eBPF
cleanup_ebpf() {
    local prog_id="$1"

    if [[ -n "$prog_id" && "$prog_id" =~ ^[0-9]+$ ]]; then
        unload_ebpf "$prog_id" || true
    fi

    # Nettoyer les programmes eBPF ChabahRoot restants
    bpftool prog show | grep chabah | while read -r line; do
        local id=$(echo "$line" | awk '{print $1}')
        unload_ebpf "$id" 2>/dev/null || true
    done

    log_info "Nettoyage eBPF complete"
}

# Execution principale
main() {
    local action="${1:-status}"
    local use_ebpf="${2:-false}"

    case "$action" in
        "integrate")
            integrate_ebpf "$use_ebpf"
            ;;
        "cleanup")
            cleanup_ebpf "$use_ebpf"
            ;;
        "status")
            if bpftool prog show | grep -q chabah; then
                log_info "Programmes eBPF charges"
                bpftool prog show | grep chabah
            else
                log_info "Aucun programme eBPF ChabahRoot charge"
            fi
            ;;
        *)
            log_error "Utilisation: $0 {integrate|cleanup|status} [use_ebpf]"
            exit 1
            ;;
    esac
}

# Executer la fonction main avec les arguments
main "$@"