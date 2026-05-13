#!/usr/bin/env bash
# This wrapper keeps the startup path short for manual runs and tests.
# The ingestion layer only has one job: validate tracefs and switch on
# the tracepoints that feed the rest of the pipeline with raw events.
# Nothing else should happen here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_separator "Starting M1 tracefs ingestion"
bash "$SCRIPT_DIR/check.sh"
bash "$SCRIPT_DIR/integration.sh" load
log_success "M1 ingestion initialized"
