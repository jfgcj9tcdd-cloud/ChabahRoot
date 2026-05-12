#!/usr/bin/env bash
# ChabahRoot M1 — Initialisation Complète du Noyau
# Lance la capture eBPF et le ring buffer pour alimenter le pipeline d'analyse
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

readonly EBPF_INTEGRATION="$SCRIPT_DIR/ebpf_integration.sh"
readonly RINGBUF_READER="$SCRIPT_DIR/../detection/ringbuf_reader.sh"
readonly M1_PIDFILE="/tmp/chabah_m1.pid"

# Vérifier les prérequis M1
verify_m1_prerequisites() {
    log_info "Vérification des prérequis M1"
    
    verify_root_privileges || return 1
    
    # Vérifier les outils kernel
    require_command bpftool "bpftool" || return 1
    require_command clang "clang" || return 1
    require_command llvm-strip "llvm-strip" || return 1
    
    # Vérifier l'accès aux tracepoints
    if [[ ! -d /sys/kernel/debug/tracing/events/syscalls ]]; then
        log_error "Accès aux tracepoints du noyau non disponible"
        log_info "Conseil: Montez debugfs avec: sudo mount -t debugfs none /sys/kernel/debug"
        return 1
    fi
    
    log_success "Tous les prérequis M1 vérifiés"
}

# Compiler et charger les programmes eBPF
load_ebpf_programs() {
    log_info "Chargement des programmes eBPF M1"
    
    # Utiliser ebpf_integration.sh pour gérer la compilation et le chargement
    if bash "$EBPF_INTEGRATION" load; then
        log_success "Programmes eBPF chargés avec succès"
        return 0
    else
        log_error "Échec du chargement des programmes eBPF"
        return 1
    fi
}

# Démarrer le lecteur du ring buffer en arrière-plan
start_ringbuf_reader() {
    log_info "Démarrage du lecteur ring buffer M1→M3"
    
    if [[ ! -f "$RINGBUF_READER" ]]; then
        log_warn "Lecteur ring buffer non trouvé: $RINGBUF_READER"
        log_info "Le ring buffer ne sera pas lu (événements perdus)"
        return 0  # Non-bloquant pour la compatibilité
    fi
    
    # Lancer le reader en arrière-plan
    bash "$RINGBUF_READER" &
    local reader_pid=$!
    
    echo "$reader_pid" > "$M1_PIDFILE.reader"
    log_success "Lecteur ring buffer démarré (PID=$reader_pid)"
}

# Nettoyer les ressources M1
cleanup_m1() {
    log_info "Nettoyage de la couche M1"
    
    # Arrêter le lecteur ring buffer
    if [[ -f "$M1_PIDFILE.reader" ]]; then
        local reader_pid
        reader_pid=$(cat "$M1_PIDFILE.reader")
        if kill -0 "$reader_pid" 2>/dev/null; then
            log_info "Arrêt du lecteur ring buffer (PID=$reader_pid)"
            kill "$reader_pid" 2>/dev/null || true
            wait "$reader_pid" 2>/dev/null || true
        fi
        rm -f "$M1_PIDFILE.reader"
    fi
    
    # Décharger les programmes eBPF
    bash "$EBPF_INTEGRATION" cleanup
    
    log_success "Couche M1 nettoyée"
}

# Handler de signal
shutdown_handler() {
    log_info "Signal d'arrêt reçu"
    cleanup_m1
    exit 0
}

# Programme principal
main() {
    case "${1:-start}" in
        start)
            log_separator "Initialisation M1: Couche d'Ingestion eBPF"
            
            verify_m1_prerequisites || exit 1
            load_ebpf_programs || exit 1
            start_ringbuf_reader || exit 1
            
            echo "$$" > "$M1_PIDFILE"
            log_success "M1 démarré et prêt (PID=$$)"
            
            # Garder le processus en vie
            trap shutdown_handler INT TERM EXIT
            
            while true; do
                sleep 1
            done
            ;;
        stop)
            log_info "Arrêt de M1"
            cleanup_m1
            ;;
        status)
            bash "$EBPF_INTEGRATION" status
            ;;
        *)
            log_info "Usage: $0 {start|stop|status}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
