#!/usr/bin/env bash
# tests/run-all.sh — Run every test_*.sh file under tests/.
#
# Usage:
#   bash tests/run-all.sh
#
# Each test file is executed in a subprocess.  Summary printed at the end.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL=0
PASSED=0
FAILED=0
ERRORS=()

for test_file in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue
    name="$(basename "$test_file")"
    TOTAL=$((TOTAL + 1))

    echo ""
    echo "═══ ${name} ═══"
    if bash "$test_file"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        ERRORS+=("$name")
    fi
done

echo ""
echo "══════════════════════════════════════════════════"
echo "  Total: ${TOTAL}  |  Passed: ${PASSED}  |  Failed: ${FAILED}"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "  Failed files:"
    for e in "${ERRORS[@]}"; do
        echo "    - ${e}"
    done
fi
echo "══════════════════════════════════════════════════"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
