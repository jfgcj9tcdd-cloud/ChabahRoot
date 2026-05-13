#!/usr/bin/env bash
# Verification des prerequis M1
# MOUSAAB EL HARMALI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib_utils.sh"

log_info "Verification des prerequis eBPF M1"
verify_root_privileges || exit 1
require_command bpftool "bpftool" || exit 1
require_command clang "clang" || exit 1
require_command llvm-strip "llvm-strip" || exit 1

if [[ ! -d /sys/kernel/debug/tracing/events/syscalls ]]; then
    log_error "Acces aux tracepoints indisponible"
    log_info "Conseil: sudo mount -t debugfs none /sys/kernel/debug"
    exit 1
fi

log_success "Tous les prerequis M1 sont valides"
