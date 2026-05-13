#!/usr/bin/env bash
# This engine evaluates normalized events and emits alerts as side files.
# The jq conditions live outside the script so the detection surface can
# change without turning shell control flow into a tangle of bespoke
# branches that nobody wants to review under pressure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../socle_commun/utilitaires.sh"
source "$SCRIPT_DIR/../socle_commun/rules.conf"

readonly DETECTION_RULES_FILE="$SCRIPT_DIR/detection_rules.json"
readonly DETECTION_STATE_DIR="/tmp/chabah_detection_state"
readonly ALERTS_FILE="$DETECTION_STATE_DIR/alerts.ndjson"
readonly ACTIONS_LOG="$DETECTION_STATE_DIR/actions.log"

prepare_detection_state() {
    mkdir -p "$DETECTION_STATE_DIR"
    touch "$ALERTS_FILE" "$ACTIONS_LOG"
}

load_detection_rules() {
    [[ -f "$DETECTION_RULES_FILE" ]] || {
        log_alert "RULES" "Missing rules file: $DETECTION_RULES_FILE"
        return 1
    }

    jq empty "$DETECTION_RULES_FILE" >/dev/null 2>&1 || {
        log_error "RULES" "Invalid JSON in $DETECTION_RULES_FILE"
        return 1
    }

    log_info "RULES" "Loaded rules from $DETECTION_RULES_FILE"
}

build_alert_json() {
    local rule_json="$1"
    local event_json="$2"

    jq -cn \
        --arg alert_id "$(uuidgen 2>/dev/null || echo "alert-$$-$RANDOM")" \
        --argjson rule "$rule_json" \
        --argjson event "$event_json" \
        --argjson created_at "$(date '+%s')" \
        '{
            alert_id: $alert_id,
            timestamp: $created_at,
            rule: {
                id: $rule.id,
                name: $rule.name,
                type: $rule.type,
                severity: $rule.severity
            },
            event: $event
        }'
}

execute_alert_actions() {
    local rule_json="$1"
    local alert_json="$2"
    local action

    while IFS= read -r action; do
        [[ -n "$action" ]] || continue

        case "$action" in
            journal)
                printf '%s\n' "$alert_json" >> "$ACTIONS_LOG"
                ;;
            email)
                log_info "ACTIONS" "Email action is not implemented"
                ;;
            slack)
                log_info "ACTIONS" "Slack action is not implemented"
                ;;
            *)
                log_warn "ACTIONS" "Unknown action: $action"
                ;;
        esac
    done < <(echo "$rule_json" | jq -r '.actions[]?')
}

generate_alert() {
    local rule_json="$1"
    local event_json="$2"
    local alert_json rule_id rule_name severity

    rule_id="$(echo "$rule_json" | jq -r '.id')"
    rule_name="$(echo "$rule_json" | jq -r '.name')"
    severity="$(echo "$rule_json" | jq -r '.severity')"
    alert_json="$(build_alert_json "$rule_json" "$event_json")"

    printf '%s\n' "$alert_json" >> "$ALERTS_FILE"
    log_alert "RULES" "Alerte [$rule_id] $rule_name (severite: $severity)"
    execute_alert_actions "$rule_json" "$alert_json"
}

evaluate_rule() {
    local rule_json="$1"
    local event_json="$2"
    local enabled condition

    enabled="$(echo "$rule_json" | jq -r '.enabled // true')"
    [[ "$enabled" == "true" ]] || return 1

    condition="$(echo "$rule_json" | jq -r '.condition // empty')"
    [[ -n "$condition" ]] || return 1

    if jq -e "$condition" >/dev/null 2>&1 <<< "$event_json"; then
        generate_alert "$rule_json" "$event_json"
        return 0
    fi

    return 1
}

apply_all_rules() {
    local event_json="$1"
    local rule_json

    while IFS= read -r rule_json; do
        [[ -n "$rule_json" ]] || continue
        evaluate_rule "$rule_json" "$event_json" || true
    done < <(jq -c '.rules[]' "$DETECTION_RULES_FILE")
}

main() {
    local event_json

    prepare_detection_state
    load_detection_rules || exit 1
    log_info "DETECTION" "M2 rules engine started"

    while IFS= read -r event_json; do
        [[ -n "${event_json// }" ]] || continue

        if ! jq empty >/dev/null 2>&1 <<< "$event_json"; then
            log_warn "DETECTION" "Dropping invalid JSON event"
            continue
        fi

        apply_all_rules "$event_json"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
