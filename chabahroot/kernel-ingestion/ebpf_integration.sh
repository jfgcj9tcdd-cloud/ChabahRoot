#!/usr/bin/env bash
# Service canonique M1 - integration eBPF
# Auteur: MOUSAAB EL HARMALI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec bash "$PROJECT_ROOT/chabahroot/m1/ebpf_integration.sh" "$@"
