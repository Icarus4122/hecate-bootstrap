#!/usr/bin/env bash
# tests/test_update_lab_summary.sh
#
# Static check that scripts/update-lab.sh's summary wording differs
# correctly between the "tools updated" and "no tooling change" cases.
# Avoids invoking the script (which needs Docker and root).
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "update-lab.sh summary wording"

REPO_DIR="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_DIR/scripts/update-lab.sh"
assert_file_exists "$SCRIPT" "update-lab.sh present"

SRC="$(cat "$SCRIPT")"

# Conditional branch must reference both flags.
assert_contains "$SRC" 'OPT_EMPUSA" == "1" || "$OPT_BINARIES" == "1"' \
    "summary: conditional checks --empusa and --binaries"

# Branch when tooling MAY have changed.
assert_contains "$SRC" "tooling under" \
    "summary: notes tooling under \${LAB_ROOT}/tools may have been updated"
assert_contains "$SRC" "Runtime data and workspaces under" \
    "summary: clarifies runtime data was untouched"

# Default branch (no tool flags).
assert_contains "$SRC" "runtime data was not modified by this script" \
    "summary: default branch retains 'not modified' wording"

end_tests
