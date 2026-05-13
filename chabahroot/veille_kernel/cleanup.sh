#!/usr/bin/env bash
# This helper gives operators one small entry point for teardown.
# It intentionally delegates to the tracefs integration layer so the
# disable order stays identical whether cleanup is manual or signaled
# by the long running orchestrator.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_info "Stopping M1 tracefs capture"
bash "$SCRIPT_DIR/integration.sh" cleanup
log_success "M1 cleanup complete"
