#!/usr/bin/env bash
# scenarios/sc_08_plugin_failures.sh - Plugin graph failure modes.
#
# Validates plugin dependency failures, blocked states, unknown
# permissions, cycle handling, and activation/dispatch isolation by
# executing local Empusa plugin contract tests.

begin_scenario "plugin-failures" "Plugin system failure modes and exception isolation"

LOCAL_EMPUSA_REPO="/opt/empusa"
PYTHON="$LOCAL_EMPUSA_REPO/.venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    skip_scenario "plugin-failures" "Empusa Python not available"
    return 0
fi

if [[ ! -d "$LOCAL_EMPUSA_REPO/tests" ]]; then
    skip_scenario "plugin-failures" "Local Empusa tests directory missing"
    return 0
fi

section "Plugin Contract Test Suite"

for t in tests/test_plugins.py; do
    if [[ -f "$LOCAL_EMPUSA_REPO/$t" ]]; then
        _record_pass "contract file exists: $t"
    else
        _record_fail "contract file exists: $t" "missing" "$LOCAL_EMPUSA_REPO/$t"
    fi
done

set +e
plugin_out="$(cd "$LOCAL_EMPUSA_REPO" && "$PYTHON" -m pytest tests/test_plugins.py -q 2>&1)"
plugin_rc=$?
set -e

assert_eq "0" "$plugin_rc" "plugin contracts: pytest exits 0"
if echo "$plugin_out" | grep -q "\[100%\]"; then
    _record_pass "plugin contracts: reached 100% completion"
else
    _record_fail "plugin contracts: reached 100% completion" "missing [100%]" "pytest completion marker"
fi

if echo "$plugin_out" | grep -qi "failed"; then
    _record_fail "plugin contracts: no failed tests" "contains 'failed'" "all plugin tests passing"
else
    _record_pass "plugin contracts: no failed tests"
fi

end_scenario
