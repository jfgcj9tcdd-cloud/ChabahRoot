#!/usr/bin/env bash
# These checks are intentionally plain because they exist for regression
# triage after shell edits. The script proves that the sample corpus can
# cross the normalized pipeline and that every maintained entry point
# still parses under bash before anyone reaches for heavier tooling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

readonly NORMALIZER="$PROJECT_ROOT/chabahroot/chaines_d_ecoute/ringbuf_reader.sh"
readonly RULES_ENGINE="$PROJECT_ROOT/chabahroot/vigie_comportementale/rules_engine.sh"

syntax_check() {
    local script

    while IFS= read -r script; do
        bash -n "$script"
    done < <(find "$PROJECT_ROOT/chabahroot" -type f -name '*.sh' | sort)
}

sample_pipeline_smoke_test() {
    local alerts

    alerts="$(
        bash "$NORMALIZER" --sample 2>/dev/null |
        timeout 2 bash "$RULES_ENGINE" 2>&1 || true
    )"

    [[ "$alerts" == *"Alerte [rule_exec_001]"* ]]
}

main() {
    syntax_check
    sample_pipeline_smoke_test
    printf 'Integration checks passed\n'
}

main "$@"
