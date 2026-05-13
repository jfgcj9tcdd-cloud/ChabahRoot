#!/usr/bin/env bash
# Ces controles restent simples parce qu ils servent au triage rapide.
# Le but est de verifier que le corpus d essai traverse bien le pipeline
# normalise et que chaque point d entree maintenu reste lisible par bash.
# Un echec ici doit apparaitre avant toute verification plus lourde.
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
