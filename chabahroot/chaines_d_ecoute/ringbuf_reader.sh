#!/usr/bin/env bash
# This stage turns unstable raw syscall text into one normalized shape.
# It accepts stdin, a file, or the sample corpus because operators need
# the same parser in live runs and in offline validation, and the rules
# engine downstream should never need to care where an event came from.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

readonly DEFAULT_SAMPLE_FILE="$PROJECT_ROOT/examples/sample_events.ndjson"

log_info() {
    printf '[INFO] [M3] %s\n' "$1" >&2
}

log_warn() {
    printf '[WARN] [M3] %s\n' "$1" >&2
}

log_error() {
    printf '[ERROR] [M3] %s\n' "$1" >&2
}

load_rules_conf() {
    if [[ -f "$SCRIPT_DIR/../socle_commun/rules.conf" ]]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/../socle_commun/rules.conf" || true
    fi
}

parse_raw_event() {
    local raw_event="$1"
    local pid ppid uid gid ts comm argv event_type

    if [[ "$raw_event" =~ pid=([0-9]+)[[:space:]]+ppid=([0-9]+)[[:space:]]+uid=([0-9]+)[[:space:]]+gid=([0-9]+)[[:space:]]+ts=([0-9]+)[[:space:]]+comm=([^[:space:]]+)[[:space:]]+argv=(.+)[[:space:]]+event_type=([0-9]+)$ ]]; then
        pid="${BASH_REMATCH[1]}"
        ppid="${BASH_REMATCH[2]}"
        uid="${BASH_REMATCH[3]}"
        gid="${BASH_REMATCH[4]}"
        ts="${BASH_REMATCH[5]}"
        comm="${BASH_REMATCH[6]}"
        argv="${BASH_REMATCH[7]}"
        event_type="${BASH_REMATCH[8]}"
    else
        return 1
    fi

    case "$event_type" in
        1) event_type="exec" ;;
        2) event_type="setuid" ;;
        3) event_type="setgid" ;;
        4) event_type="prctl_caps" ;;
        *) event_type="unknown" ;;
    esac

    jq -cn \
        --argjson pid "$pid" \
        --argjson ppid "$ppid" \
        --argjson uid "$uid" \
        --argjson gid "$gid" \
        --argjson ts "$ts" \
        --arg comm "$comm" \
        --arg argv "$argv" \
        --arg event_type "$event_type" \
        '{
            timestamp: ($ts / 1000000000 | floor),
            timestamp_ns: $ts,
            event_type: $event_type,
            process: {
                pid: $pid,
                ppid: $ppid,
                comm: $comm
            },
            credentials: {
                uid: $uid,
                gid: $gid
            },
            data: {
                argv: $argv
            }
        }'
}

ensure_normalized_shape() {
    local json="$1"

    echo "$json" | jq -c '
        {
            timestamp: (.timestamp // ((.timestamp_ns // 0) / 1000000000 | floor)),
            timestamp_ns: (.timestamp_ns // (.timestamp * 1000000000)),
            event_type: (.event_type // "unknown"),
            process: {
                pid: (.process.pid // 0),
                ppid: (.process.ppid // 0),
                comm: (.process.comm // "unknown"),
                cmdline: (.process.cmdline // "")
            },
            credentials: {
                uid: (.credentials.uid // 0),
                gid: (.credentials.gid // 0)
            },
            data: {
                argv: (.data.argv // "")
            }
        }'
}

enrich_event_with_parent_context() {
    local json="$1"
    local ppid parent_comm parent_cmdline

    ppid="$(echo "$json" | jq -r '.process.ppid // 0')"

    if [[ "$ppid" =~ ^[0-9]+$ ]] && [[ "$ppid" -gt 0 ]]; then
        if [[ -r "/proc/$ppid/comm" ]]; then
            parent_comm="$(tr -d '\n' < "/proc/$ppid/comm" 2>/dev/null || true)"
        else
            parent_comm="unknown"
        fi

        if [[ -r "/proc/$ppid/cmdline" ]]; then
            parent_cmdline="$(tr '\0' ' ' < "/proc/$ppid/cmdline" 2>/dev/null || true)"
        else
            parent_cmdline=""
        fi
    else
        parent_comm="unknown"
        parent_cmdline=""
    fi

    echo "$json" | jq -c --arg pcomm "$parent_comm" --arg pcmd "$parent_cmdline" '
        .process.parent_comm = (if $pcomm == "" then "unknown" else $pcomm end)
        | .process.parent_cmdline = $pcmd'
}

filter_sensitive_data() {
    local json="$1"
    local keywords

    keywords="${SENSITIVE_KEYWORDS:-pass password token secret key}"

    echo "$json" | jq -c --arg keywords "$keywords" '
        ($keywords | split(" ")) as $k
        | .data.argv |= (
            if . == null then ""
            else
                reduce $k[] as $item (.;
                    if $item == "" then .
                    elif test($item; "i") then "[REDACTED]"
                    else .
                    end
                )
            end
        )'
}

normalize_for_output() {
    local json="$1"

    echo "$json" | jq -c '
        .normalized_at = (now | floor)
        | .source = (.source // "chaines_d_ecoute")'
}

decode_event_line() {
    local line="$1"

    [[ -z "${line// }" ]] && return 1

    if jq -e . >/dev/null 2>&1 <<< "$line"; then
        ensure_normalized_shape "$line"
        return 0
    fi

    parse_raw_event "$line"
}

process_stream() {
    local source_label="$1"
    local line decoded enriched filtered normalized

    log_info "Reading event stream from $source_label"

    while IFS= read -r line; do
        decoded="$(decode_event_line "$line")" || {
            log_warn "Dropping unparsable event"
            continue
        }

        enriched="$(enrich_event_with_parent_context "$decoded")"
        filtered="$(filter_sensitive_data "$enriched")"
        normalized="$(normalize_for_output "$filtered")"
        echo "$normalized"
    done
}

main() {
    local input_mode="${1:-auto}"

    load_rules_conf

    case "$input_mode" in
        --stdin)
            process_stream "stdin"
            ;;
        --input)
            local input_file="${2:-}"
            if [[ -z "$input_file" ]] || [[ ! -f "$input_file" ]]; then
                log_error "Invalid source file for --input"
                exit 1
            fi
            process_stream "$input_file" < "$input_file"
            ;;
        --sample)
            if [[ ! -f "$DEFAULT_SAMPLE_FILE" ]]; then
                log_error "Sample file is missing: $DEFAULT_SAMPLE_FILE"
                exit 1
            fi
            process_stream "$DEFAULT_SAMPLE_FILE" < "$DEFAULT_SAMPLE_FILE"
            ;;
        auto)
            if [[ -n "${CHABAH_EVENT_SOURCE:-}" ]]; then
                if [[ ! -e "$CHABAH_EVENT_SOURCE" ]]; then
                    log_error "CHABAH_EVENT_SOURCE is missing: $CHABAH_EVENT_SOURCE"
                    exit 1
                fi
                process_stream "$CHABAH_EVENT_SOURCE" < "$CHABAH_EVENT_SOURCE"
            elif [[ -p /dev/stdin ]]; then
                process_stream "stdin"
            elif [[ -f "$DEFAULT_SAMPLE_FILE" ]] && [[ "${CHABAH_ALLOW_SAMPLE_FALLBACK:-0}" == "1" ]]; then
                log_warn "No live source found; using sample fallback"
                process_stream "$DEFAULT_SAMPLE_FILE" < "$DEFAULT_SAMPLE_FILE"
            else
                log_error "No event source is available"
                log_error "Use --sample, --input <file>, --stdin, or CHABAH_EVENT_SOURCE"
                exit 1
            fi
            ;;
        *)
            log_error "Usage: $0 [--stdin|--input <file>|--sample]"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
