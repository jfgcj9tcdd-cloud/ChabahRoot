#!/usr/bin/env bash
# ChabahRoot M3 — Lecteur de Ring Buffer et Normalisation d'Événements
# Lit les événements eBPF depuis le ring buffer et les normalise pour analyse
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib_utils.sh"
source "$SCRIPT_DIR/rules.conf" 2>/dev/null || true

readonly RINGBUF_MAP="/sys/fs/bpf/chabah_events"
readonly EVENT_QUEUE="/tmp/chabah_event_queue.fifo"
readonly EVENT_CACHE="/tmp/chabah_events.cache"

# Initialiser le reader du ring buffer
init_ringbuf_reader() {
    log_info "Initialisation du lecteur ring buffer eBPF"
    
    # Vérifier que le map eBPF est chargé
    if [[ ! -e "$RINGBUF_MAP" ]]; then
        log_error "Ring buffer eBPF non trouvé: $RINGBUF_MAP"
        return 1
    fi
    
    # Créer une FIFO pour les événements en queue
    if [[ ! -p "$EVENT_QUEUE" ]]; then
        mkfifo "$EVENT_QUEUE" 2>/dev/null || true
    fi
    
    log_success "Ring buffer reader initialisé"
}

# Décoder un événement brut du ring buffer en structure JSON
decode_ebpf_event() {
    local raw_event="$1"
    
    # Format attendu: pid=X ppid=Y uid=Z gid=W ts=T comm=C argv=A event_type=E
    # Exemple: pid=1234 ppid=1 uid=1000 gid=1000 ts=1234567890 comm=bash argv=/bin/bash event_type=1
    
    # Parser le raw event (format hexadecimal ou texte)
    local pid ppid uid gid ts comm argv event_type
    
    if [[ $raw_event =~ pid=([0-9]+)\ ppid=([0-9]+)\ uid=([0-9]+)\ gid=([0-9]+)\ ts=([0-9]+)\ comm=([^ ]+)\ argv=([^ ]+)\ event_type=([0-9]+) ]]; then
        pid="${BASH_REMATCH[1]}"
        ppid="${BASH_REMATCH[2]}"
        uid="${BASH_REMATCH[3]}"
        gid="${BASH_REMATCH[4]}"
        ts="${BASH_REMATCH[5]}"
        comm="${BASH_REMATCH[6]}"
        argv="${BASH_REMATCH[7]}"
        event_type="${BASH_REMATCH[8]}"
    else
        # Format hexadecimal - implémenter le décodage si nécessaire
        log_debug "Événement brut non parsable: $raw_event"
        return 1
    fi
    
    # Traduire event_type en libellé
    local event_type_name
    case "$event_type" in
        1) event_type_name="exec" ;;
        2) event_type_name="setuid" ;;
        3) event_type_name="setgid" ;;
        4) event_type_name="prctl_caps" ;;
        *) event_type_name="unknown" ;;
    esac
    
    # Formater en JSON normalisé
    cat <<EOF
{
  "timestamp": $(date -d "@$((ts / 1000000000))" '+%s'),
  "timestamp_ns": $ts,
  "event_type": "$event_type_name",
  "process": {
    "pid": $pid,
    "ppid": $ppid,
    "comm": "$comm"
  },
  "credentials": {
    "uid": $uid,
    "gid": $gid
  },
  "data": {
    "argv": "$argv"
  }
}
EOF
}

# Enrichir un événement normalisé avec contexte parent
enrich_event_with_parent_context() {
    local json="$1"
    local pid
    
    pid=$(echo "$json" | grep -oP '"pid":\s*\K[0-9]+' | head -1)
    
    if [[ -z "$pid" ]]; then
        echo "$json"
        return 0
    fi
    
    # Récupérer le processus parent depuis /proc
    local parent_comm parent_cmdline
    
    if [[ -f "/proc/$pid/comm" ]]; then
        parent_comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "unknown")
    else
        parent_comm="unknown"
    fi
    
    if [[ -f "/proc/$pid/cmdline" ]]; then
        parent_cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "unknown")
    else
        parent_cmdline="unknown"
    fi
    
    # Ajouter le contexte au JSON
    echo "$json" | jq --arg pcomm "$parent_comm" --arg pcmd "$parent_cmdline" \
        '.process.parent_comm = $pcomm | .process.cmdline = $pcmd'
}

# Filtrer les événements selon les règles sensibles
filter_sensitive_data() {
    local json="$1"
    local argv
    
    argv=$(echo "$json" | jq -r '.data.argv // ""')
    
    # Vérifier les mots-clés sensibles
    local sensitive_keywords="${SENSITIVE_KEYWORDS:-password token secret key}"
    
    for keyword in $sensitive_keywords; do
        if [[ "$argv" =~ $keyword ]]; then
            # Masquer la valeur sensible
            argv="${argv//[a-zA-Z0-9=_-]*$keyword[a-zA-Z0-9=_-]*/[REDACTED]}"
        fi
    done
    
    # Retourner le JSON filtré
    echo "$json" | jq --arg argv "$argv" '.data.argv = $argv'
}

# Lire les événements depuis le ring buffer en continu
read_from_ringbuf() {
    log_info "Lecture des événements depuis ring buffer eBPF"
    
    # Utiliser bpftool pour lire le ring buffer
    # Note: Cela nécessite une version récente de bpftool
    
    # Alternative: utiliser perf ou un script C pour lire le ring buffer
    # Pour MVP: simulation avec journalctl ou /proc/sys/kernel/bpf
    
    # En attendant un vrai lecteur ring buffer, utiliser journalctl comme fallback
    journalctl -u chabahroot -f 2>/dev/null | while read -r line; do
        echo "$line" >> "$EVENT_CACHE"
    done
}

# Traiter un batch d'événements du cache
process_event_batch() {
    local max_events="${1:-100}"
    local processed=0
    
    # Lire les événements du cache
    if [[ ! -f "$EVENT_CACHE" ]]; then
        return 0
    fi
    
    # Traiter et supprimer les événements traités
    head -n "$max_events" "$EVENT_CACHE" | while IFS= read -r line; do
        # Décoder l'événement
        local decoded
        decoded=$(decode_ebpf_event "$line") || continue
        
        # Enrichir avec contexte
        decoded=$(enrich_event_with_parent_context "$decoded")
        
        # Filtrer données sensibles
        decoded=$(filter_sensitive_data "$decoded")
        
        # Passer à la couche analyse (M2)
        echo "$decoded"
        
        ((processed++))
    done
    
    # Supprimer les lignes traitées du cache
    if (( processed > 0 )); then
        tail -n +$((processed + 1)) "$EVENT_CACHE" > "${EVENT_CACHE}.tmp"
        mv "${EVENT_CACHE}.tmp" "$EVENT_CACHE" 2>/dev/null || true
    fi
}

# Normaliser les événements pour stockage cohérent
normalize_for_output() {
    local json="$1"
    
    # Assurer les champs requis
    echo "$json" | jq '{
        timestamp: .timestamp,
        timestamp_ns: .timestamp_ns,
        event_type: .event_type,
        process: .process,
        credentials: .credentials,
        data: .data,
        normalized_at: (now | tostring)
    }'
}

# Programme principal
main() {
    init_ringbuf_reader || exit 1
    
    log_info "Démarrage du lecteur ring buffer pour M2"
    
    # Boucle continue de lecture
    while true; do
        process_event_batch 50
        sleep 0.1  # Polling interval
    done
}

# Arrêt gracieux
cleanup() {
    log_info "Arrêt du lecteur ring buffer"
    rm -f "$EVENT_QUEUE" 2>/dev/null || true
    exit 0
}

trap cleanup INT TERM EXIT

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
