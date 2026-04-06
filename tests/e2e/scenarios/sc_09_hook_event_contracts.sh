#!/usr/bin/env bash
# scenarios/sc_09_hook_event_contracts.sh - Hook/event contract validation.
#
# Validates event payload contracts, pre_* event behavior, hook adapter
# behavior, and subscriber exception isolation via local Empusa tests.

begin_scenario "hook-event-contracts" "Event payload contracts and hook system guarantees"

LOCAL_EMPUSA_REPO="/opt/empusa"
PYTHON="$LOCAL_EMPUSA_REPO/.venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    skip_scenario "hook-event-contracts" "Empusa Python not available"
    return 0
fi

if [[ ! -d "$LOCAL_EMPUSA_REPO/tests" ]]; then
    skip_scenario "hook-event-contracts" "Local Empusa tests directory missing"
    return 0
fi

section "Event + Hook Contract Test Suite"

contract_tests=(
    "tests/test_bus.py"
    "tests/test_events.py"
    "tests/test_cli_hooks.py"
    "tests/test_cli_workspace.py"
    "tests/test_workspace_build_e2e.py"
)

for t in "${contract_tests[@]}"; do
    if [[ -f "$LOCAL_EMPUSA_REPO/$t" ]]; then
        _record_pass "contract file exists: $t"
    else
        _record_fail "contract file exists: $t" "missing" "$LOCAL_EMPUSA_REPO/$t"
    fi
done

set +e
hook_out="$(cd "$LOCAL_EMPUSA_REPO" && "$PYTHON" -m pytest \
    tests/test_bus.py \
    tests/test_events.py \
    tests/test_cli_hooks.py \
    tests/test_cli_workspace.py \
    tests/test_workspace_build_e2e.py \
    -q 2>&1)"
hook_rc=$?
set -e

assert_eq "0" "$hook_rc" "hook/event contracts: pytest exits 0"
if echo "$hook_out" | grep -q "\[100%\]"; then
    _record_pass "hook/event contracts: reached 100% completion"
else
    _record_fail "hook/event contracts: reached 100% completion" "missing [100%]" "pytest completion marker"
fi

if echo "$hook_out" | grep -qi "failed"; then
    _record_fail "hook/event contracts: no failed tests" "contains 'failed'" "all hook/event tests passing"
else
    _record_pass "hook/event contracts: no failed tests"
fi

end_scenario
