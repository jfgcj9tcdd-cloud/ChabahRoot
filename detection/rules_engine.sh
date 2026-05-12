#!/usr/bin/env bash
# ChabahRoot M2 — Moteur de Détection (Rules Engine)
# Analyse des événements eBPF selon des règles configurables
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/rules.conf"

readonly DETECTION_RULES_FILE="${SCRIPT_DIR}/detection_rules.json"
readonly DETECTION_STATE="/tmp/chabah_detection_state"

# Charger les règles de détection depuis le fichier JSON
load_detection_rules() {
    if [[ ! -f "$DETECTION_RULES_FILE" ]]; then
        log_alert "RULES" "Fichier de règles non trouvé: $DETECTION_RULES_FILE"
        return 1
    fi
    
    # Valider le JSON
    jq empty "$DETECTION_RULES_FILE" 2>/dev/null || {
        log_error "RULES" "Fichier de règles JSON invalide"
        return 1
    }
    
    log_info "RULES" "Règles de détection chargées depuis $DETECTION_RULES_FILE"
}

# Évaluer une règle contre un événement
evaluate_rule() {
    local rule_json="$1"
    local event_json="$2"
    
    # Extraire les conditions de la règle
    local rule_id rule_name rule_type severity condition
    
    rule_id=$(echo "$rule_json" | jq -r '.id')
    rule_name=$(echo "$rule_json" | jq -r '.name')
    rule_type=$(echo "$rule_json" | jq -r '.type')
    severity=$(echo "$rule_json" | jq -r '.severity')
    condition=$(echo "$rule_json" | jq -r '.condition')
    
    # Évaluer la condition (jq filter)
    if echo "$event_json" | jq -e "$condition" >/dev/null 2>&1; then
        # Condition matchée - générer une alerte
        generate_alert "$rule_id" "$rule_name" "$rule_type" "$severity" "$event_json"
        return 0
    fi
    
    return 1
}

# Générer une alerte structurée
generate_alert() {
    local rule_id="$1" rule_name="$2" rule_type="$3" severity="$4" event_json="$5"
    
    local alert_json
    alert_json=$(cat <<EOF
{
  "alert_id": "$(uuidgen 2>/dev/null || echo 'alert-'$$'-'$RANDOM)",
  "timestamp": $(date '+%s'),
  "rule": {
    "id": "$rule_id",
    "name": "$rule_name",
    "type": "$rule_type",
    "severity": "$severity"
  },
  "event": $event_json
}
EOF
    )
    
    # Logger l'alerte
    log_alert "$rule_type" "Alerte de règle [$rule_id]: $rule_name (sévérité: $severity)"
    
    # Sauvegarder l'alerte dans le state
    echo "$alert_json" >> "$DETECTION_STATE"
    
    # Exécuter les actions associées
    execute_alert_actions "$rule_json"
}

# Exécuter les actions d'une alerte (notification, escalade, etc.)
execute_alert_actions() {
    local rule_json="$1"
    
    local actions
    actions=$(echo "$rule_json" | jq -r '.actions[]?')
    
    while IFS= read -r action; do
        [[ -z "$action" ]] && continue
        
        case "$action" in
            email)
                # TODO: Envoyer notification email
                log_info "ACTIONS" "Email notification (not implemented)"
                ;;
            slack)
                # TODO: Envoyer notification Slack
                log_info "ACTIONS" "Slack notification (not implemented)"
                ;;
            journal)
                # Écrire dans systemd journal
                journalctl -t chabahroot --vacuum-time=1d >/dev/null 2>&1 || true
                ;;
            *)
                log_warn "RULES" "Action non reconnue: $action"
                ;;
        esac
    done <<< "$actions"
}

# Détecteur de privilege escalation - UID transition
detect_privilege_escalation() {
    local event_json="$1"
    
    local event_type uid ppid comm
    
    event_type=$(echo "$event_json" | jq -r '.event_type')
    uid=$(echo "$event_json" | jq -r '.credentials.uid')
    ppid=$(echo "$event_json" | jq -r '.process.ppid')
    comm=$(echo "$event_json" | jq -r '.process.comm')
    
    # Détecter transitions setuid/setgid
    if [[ "$event_type" =~ setuid|setgid ]]; then
        local target_uid target_gid
        target_uid=$(echo "$event_json" | jq -r '.data.argv' | grep -oP 'setuid\(\K[0-9]+' || echo "0")
        
        # Si transition vers UID=0, c'est suspect
        if [[ "$target_uid" == "0" ]] && [[ "$uid" != "0" ]]; then
            return 0  # Match!
        fi
    fi
    
    # Détecter les processus root suspects
    if [[ "$uid" == "0" ]] && [[ "$ppid" != "1" ]]; then
        # Root process avec parent normal (pas init) - potentiellement suspect
        local suspicious_procs="nc ncat netcat bash sh perl python ruby"
        
        for proc in $suspicious_procs; do
            if [[ "$comm" == "$proc" ]]; then
                return 0  # Match!
            fi
        done
    fi
    
    return 1
}

# Détecteur d'exécution suspecte
detect_suspicious_execution() {
    local event_json="$1"
    
    local argv comm uid
    argv=$(echo "$event_json" | jq -r '.data.argv')
    comm=$(echo "$event_json" | jq -r '.process.comm')
    uid=$(echo "$event_json" | jq -r '.credentials.uid')
    
    # Détecter les chaînes de commande suspectes
    local suspicious_patterns="curl|wget.*http|bash.*nc|/dev/tcp|nmap|masscan"
    
    if [[ "$argv" =~ $suspicious_patterns ]]; then
        return 0  # Match!
    fi
    
    # Détecter les binaires lancés depuis /tmp, /dev/shm
    if [[ "$argv" =~ ^(/tmp|/dev/shm|/var/tmp)/ ]]; then
        return 0  # Match!
    fi
    
    return 1
}

# Détecteur de capability abuse
detect_capability_abuse() {
    local event_json="$1"
    
    local event_type uid
    event_type=$(echo "$event_json" | jq -r '.event_type')
    uid=$(echo "$event_json" | jq -r '.credentials.uid')
    
    # Détecter modifications de capabilities
    if [[ "$event_type" == "prctl_caps" ]]; then
        # Toute modification de capabilities par user non-root est suspecte
        if [[ "$uid" != "0" ]]; then
            return 0  # Match!
        fi
    fi
    
    return 1
}

# Appliquer toutes les règles chargées à un événement
apply_all_rules() {
    local event_json="$1"
    
    # Charger les règles si nécessaire
    load_detection_rules || return 1
    
    # Itérer sur chaque règle
    local rules_count
    rules_count=$(jq '.rules | length' "$DETECTION_RULES_FILE")
    
    for ((i=0; i < rules_count; i++)); do
        local rule
        rule=$(jq ".rules[$i]" "$DETECTION_RULES_FILE")
        
        # Évaluer la règle
        evaluate_rule "$rule" "$event_json" || true
    done
}

# Programme principal pour pipeline d'analyse
main() {
    log_info "DETECTION" "Moteur de détection M2 démarré"
    
    # Lire les événements depuis stdin (provenant de M3)
    while IFS= read -r event_json; do
        [[ -z "$event_json" ]] && continue
        
        # Appliquer les règles
        apply_all_rules "$event_json" || true
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
