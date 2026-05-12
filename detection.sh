#!/bin/bash
# ChabahRoot UID Transition Detector
# Monitors systemd journal for privilege escalation events
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/var/log/chabah_detection.log"
FILTER_KEYWORDS="COMMAND="

# Ensure log file is writable
if [[ ! -w "$(dirname "$LOGFILE")" ]]; then
    LOGFILE="./chabah_detection.log"
fi

# Signal handling
cleanup() {
    echo "Detection stopped." >&2
    exit 0
}
trap cleanup INT TERM

# Log to file (append with timestamp)
log_event() {
    local msg="$1"
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOGFILE"
}

# Main detection loop - watch journalctl for sudo transitions
journalctl -f -t sudo 2>/dev/null | while read -r line; do
    if [[ "$line" == *"$FILTER_KEYWORDS"* ]]; then
        # Extract command and user context
        command_run=$(echo "$line" | grep -oP 'COMMAND=\K[^; ]*' || echo "unknown")
        
        if [[ -n "$command_run" ]]; then
            msg="Privilege transition detected: $command_run"
            log_event "$msg"
            
            # Optional desktop notification (skip if display unavailable)
            if command -v notify-send &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
                notify-send "ChabahRoot Alert" "$msg" -i dialog-warning 2>/dev/null || true
            fi
        fi
    fi
done
