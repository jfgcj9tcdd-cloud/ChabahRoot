#!/usr/bin/env bash
# ============================================================
# ChabahRoot - Module : logger.sh
# Description : Gestion centralisée des journaux structurés
# Auteur : Module Analyste Cyber
# Version : 1.0.0
# ============================================================

# Charger la configuration si elle n'est pas déjà chargée
if [[ -z "$LOG_FILE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/rules.conf" || {
        echo "[ERREUR] Impossible de charger rules.conf" >&2
        exit 1
    }
fi

# --- Codes couleur ANSI pour la console ---
COLOR_RESET="\033[0m"
COLOR_INFO="\033[0;34m"      # Bleu
COLOR_WARN="\033[0;33m"      # Jaune
COLOR_ALERT="\033[0;31m"     # Rouge
COLOR_DEBUG="\033[0;36m"     # Cyan
COLOR_SUCCESS="\033[0;32m"   # Vert

# -------------------------------------------------------
# Fonction : init_log
# Description : Initialise le fichier de log
# -------------------------------------------------------
init_log() {
    # Vérifie que le répertoire parent existe et est accessible en écriture
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"

    # Crée le répertoire s'il n'existe pas
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "[ERREUR] Impossible de créer le répertoire de log : $log_dir" >&2
            return 1
        }
    fi

    if [[ ! -w "$log_dir" ]]; then
        echo "[ERREUR] Permission refusée pour écrire dans : $log_dir" >&2
        return 1
    fi

    # Crée ou vide le fichier de log avec un en-tête structuré
    {
        echo "============================================================"
        echo "  ${PROJECT_NAME} - ${MODULE_NAME} v${VERSION}"
        echo "  Session démarrée : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  PID principal    : $$"
        echo "  Hôte             : $(hostname)"
        echo "  Utilisateur      : $(whoami) (UID=$(id -u))"
        echo "============================================================"
    } >> "$LOG_FILE" 2>/dev/null || {
        echo "[ERREUR] Impossible d'écrire dans $LOG_FILE" >&2
        return 1
    }

    return 0
}

# -------------------------------------------------------
# Fonction : log_message
# Description : Écrit un message formaté dans le log et la console
# Arguments :
#   $1 - Niveau : INFO | WARN | ALERT | DEBUG
#   $2 - Catégorie (ex: DEFENSIVE, OFFENSIVE, SYSTEM)
#   $3 - Message texte
# -------------------------------------------------------
log_message() {
    local level="$1"
    local category="$2"
    local message="$3"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local caller_uid
    caller_uid="$(id -u)"

    # Filtrage du niveau de log
    case "$LOG_LEVEL" in
        DEBUG)  ;; # Tout afficher
        INFO)   [[ "$level" == "DEBUG" ]] && return 0 ;;
        WARN)   [[ "$level" == "DEBUG" || "$level" == "INFO" ]] && return 0 ;;
        ALERT)  [[ "$level" != "ALERT" ]] && return 0 ;;
    esac

    # Format structuré du log : [TIMESTAMP] [LEVEL] [CATEGORY] [UID] MESSAGE
    local log_entry="[$timestamp] [$level] [$category] [UID=$caller_uid] $message"

    # Écriture dans le fichier de log
    echo "$log_entry" >> "$LOG_FILE" 2>/dev/null

    # Affichage coloré en console selon le niveau
    local color="$COLOR_INFO"
    case "$level" in
        WARN)  color="$COLOR_WARN" ;;
        ALERT) color="$COLOR_ALERT" ;;
        DEBUG) color="$COLOR_DEBUG" ;;
    esac

    echo -e "${color}${log_entry}${COLOR_RESET}"
}

# -------------------------------------------------------
# Fonction : log_alert
# Description : Raccourci pour les alertes critiques
# Arguments : $1 - catégorie, $2 - message
# -------------------------------------------------------
log_alert() {
    log_message "ALERT" "$1" "$2"
}

# -------------------------------------------------------
# Fonction : log_info
# Description : Raccourci pour les messages d'information
# Arguments : $1 - catégorie, $2 - message
# -------------------------------------------------------
log_info() {
    log_message "INFO" "$1" "$2"
}

# -------------------------------------------------------
# Fonction : log_warn
# Description : Raccourci pour les avertissements
# Arguments : $1 - catégorie, $2 - message
# -------------------------------------------------------
log_warn() {
    log_message "WARN" "$1" "$2"
}

# -------------------------------------------------------
# Fonction : log_debug
# Description : Raccourci pour le mode debug
# Arguments : $1 - catégorie, $2 - message
# -------------------------------------------------------
log_debug() {
    log_message "DEBUG" "$1" "$2"
}

# -------------------------------------------------------
# Fonction : filter_sensitive
# Description : Détecte les mots-clés sensibles dans un texte
# Arguments : $1 - texte à analyser
# Retour : 0 si mot-clé trouvé, 1 sinon
# -------------------------------------------------------
filter_sensitive() {
    local text="$1"
    local found=1

    for keyword in $SENSITIVE_KEYWORDS; do
        # Recherche insensible à la casse
        if echo "$text" | grep -qi "$keyword"; then
            log_alert "FILTER" "Mot-clé sensible détecté : '$keyword' dans : $(echo "$text" | head -c 80)"
            found=0
        fi
    done

    return $found
}

# -------------------------------------------------------
# Fonction : log_separator
# Description : Écrit un séparateur visuel dans les logs
# Arguments : $1 - titre optionnel
# -------------------------------------------------------
log_separator() {
    local title="${1:-}"
    local line="------------------------------------------------------------"
    if [[ -n "$title" ]]; then
        echo "$line [ $title ] $line" >> "$LOG_FILE" 2>/dev/null
        echo -e "${COLOR_SUCCESS}$line [ $title ]${COLOR_RESET}"
    else
        echo "$line" >> "$LOG_FILE" 2>/dev/null
        echo -e "${COLOR_SUCCESS}${line}${COLOR_RESET}"
    fi
}
