#!/usr/bin/env bash
# scripts/dev/ci-syntax-check.sh — Validate bash syntax across the repo.
#
# Runs `bash -n` on all shell scripts to catch parse errors before tests.
# Fast, no dependencies beyond bash itself.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ERRORS=0

check() {
    local f="$1"
    if bash -n "$f" 2>/dev/null; then
        echo "  ✓ $f"
    else
        echo "  ✗ $f"
        bash -n "$f" 2>&1 | sed 's/^/    /'
        ERRORS=$((ERRORS + 1))
    fi
}

echo "── Shell syntax check ──"

# Core scripts
for f in "$REPO"/labctl "$REPO"/scripts/*.sh "$REPO"/scripts/lib/*.sh; do
    [[ -f "$f" ]] && check "$f"
done

# Test files
for f in "$REPO"/tests/helpers.sh "$REPO"/tests/run-all.sh "$REPO"/tests/test_*.sh; do
    [[ -f "$f" ]] && check "$f"
done

# E2E harness
for f in "$REPO"/tests/e2e/e2e-helpers.sh "$REPO"/tests/e2e/run-validation.sh; do
    [[ -f "$f" ]] && check "$f"
done

# Dev scripts
for f in "$REPO"/scripts/dev/*.sh; do
    [[ -f "$f" ]] && check "$f"
done

echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo "✗ $ERRORS file(s) have syntax errors"
    exit 1
fi
echo "✓ All files pass syntax check"
