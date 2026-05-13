#!/usr/bin/env bash
# This compatibility entry point stays because operators still reach for
# orchestrator.sh out of habit. The real work now lives in run_detection,
# and keeping the jump here avoids duplicating control flow in two files
# that would drift the next time the pipeline changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$SCRIPT_DIR/run_detection.sh" "$@"
