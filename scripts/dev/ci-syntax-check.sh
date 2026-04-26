#!/usr/bin/env bash
# scripts/dev/ci-syntax-check.sh — Validate bash syntax across the repo.
#
# Runs `bash -n` on all shell scripts to catch parse errors before tests.
# Fast, no dependencies beyond bash itself.
set -euo pipefail
shopt -s nullglob

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ERRORS=0
CHECKED=0

check() {
    local f="$1"
    CHECKED=$((CHECKED + 1))
    if bash -n "$f" 2>/dev/null; then
        echo "  [PASS] ${f#$REPO/}"
    else
        echo "  [FAIL] ${f#$REPO/}"
        bash -n "$f" 2>&1 | sed 's/^/    /'
        ERRORS=$((ERRORS + 1))
    fi
}

echo "── Shell syntax check ──"

# Globs are guarded with `shopt -s nullglob` so an empty match expands to
# nothing instead of being treated as a literal filename.
TARGETS=(
    "$REPO"/labctl
    "$REPO"/scripts/*.sh
    "$REPO"/scripts/lib/*.sh
    "$REPO"/scripts/dev/*.sh
    "$REPO"/tests/helpers.sh
    "$REPO"/tests/run-all.sh
    "$REPO"/tests/test_*.sh
    "$REPO"/tests/e2e/e2e-helpers.sh
    "$REPO"/tests/e2e/run-validation.sh
    "$REPO"/tests/e2e/stage_*.sh
    "$REPO"/tests/e2e/scenarios/*.sh
    "$REPO"/tmux/profiles/*.sh
)

for f in "${TARGETS[@]}"; do
    [[ -f "$f" ]] && check "$f"
done

echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo "[FAIL] $ERRORS file(s) have syntax errors (checked $CHECKED)"
    exit 1
fi
echo "[PASS] All $CHECKED files pass syntax check"
