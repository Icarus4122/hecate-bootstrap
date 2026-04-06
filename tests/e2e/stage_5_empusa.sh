#!/usr/bin/env bash
# tests/e2e/stage_5_empusa.sh - Empusa subsystem validation.
#
# No Docker required. Validates CLI availability, workspace lifecycle,
# and runs local Empusa contract tests for plugins, hooks/events,
# subscriber isolation, permissions, cycles, and ArtifactWriter safety.

begin_stage 5 "Empusa Subsystem"

LAB="${LAB_ROOT:-/opt/lab}"
EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"
LOCAL_EMPUSA_REPO="/opt/empusa"
LOCAL_PYTHON="$LOCAL_EMPUSA_REPO/.venv/bin/python"

# ═══════════════════════════════════════════════════════════════════
#  5.0  Gate check
# ═══════════════════════════════════════════════════════════════════

if [[ ! -x "$EMPUSA_BIN" ]]; then
    _record_fail "Empusa: binary exists" "missing" "$EMPUSA_BIN"
    echo "# Empusa not installed - skipping subsystem tests"
    end_stage
    return 0 2>/dev/null || exit 0
fi

_record_pass "Empusa: binary exists"

# ═══════════════════════════════════════════════════════════════════
#  5.1  CLI availability
# ═══════════════════════════════════════════════════════════════════
section "CLI Availability"

ver_out="$($EMPUSA_BIN --version 2>&1)" || true
assert_match "$ver_out" '[0-9]+\.[0-9]+' "empusa --version: returns version"

help_out="$($EMPUSA_BIN --help 2>&1)" || true
assert_contains "$help_out" "workspace" "empusa --help: mentions workspace"
assert_contains "$help_out" "build" "empusa --help: mentions build"
assert_contains "$help_out" "plugins" "empusa --help: mentions plugins"

# ═══════════════════════════════════════════════════════════════════
#  5.2  Workspace creation - all profiles
# ═══════════════════════════════════════════════════════════════════
section "Workspace Creation"

make_sandbox
WS_ROOT="$SANDBOX/workspaces"
TEMPLATES_DIR="$REPO_ROOT/templates"
mkdir -p "$WS_ROOT"

declare -A PROFILE_DIRS
PROFILE_DIRS[htb]="notes scans web creds loot exploits screenshots reports logs"
PROFILE_DIRS[build]="src out notes logs"
PROFILE_DIRS[research]="notes references poc logs"
PROFILE_DIRS[internal]="notes scans creds loot evidence exploits reports logs"

declare -A PROFILE_TEMPLATES
PROFILE_TEMPLATES[htb]="engagement.md target.md recon.md services.md finding.md privesc.md web.md"
PROFILE_TEMPLATES[build]=""
PROFILE_TEMPLATES[research]="recon.md"
PROFILE_TEMPLATES[internal]="engagement.md target.md recon.md services.md finding.md pivot.md privesc.md ad.md"

for profile in htb build research internal; do
    ws_name="e2e-${profile}-test"

    ws_out="$($EMPUSA_BIN workspace init \
        --name "$ws_name" \
        --profile "$profile" \
        --root "$WS_ROOT" \
        --templates-dir "$TEMPLATES_DIR" \
        --set-active 2>&1)" || true

    ws_path="$WS_ROOT/$ws_name"
    assert_dir_exists "$ws_path" "ws $profile: directory created"

    for d in ${PROFILE_DIRS[$profile]}; do
        assert_dir_exists "$ws_path/$d" "ws $profile: dir $d"
    done

    assert_file_exists "$ws_path/.empusa-workspace.json" "ws $profile: metadata exists"

    for tmpl in ${PROFILE_TEMPLATES[$profile]}; do
        assert_file_exists "$ws_path/$tmpl" "ws $profile: template $tmpl seeded"
        assert_file_not_empty "$ws_path/$tmpl" "ws $profile: template $tmpl non-empty"
    done
done

# ═══════════════════════════════════════════════════════════════════
#  5.3  Workspace idempotency and selection
# ═══════════════════════════════════════════════════════════════════
section "Workspace Idempotency"

ws_re_out="$($EMPUSA_BIN workspace init \
    --name "e2e-htb-test" \
    --profile "htb" \
    --root "$WS_ROOT" \
    --templates-dir "$TEMPLATES_DIR" 2>&1)" || true

assert_dir_exists "$WS_ROOT/e2e-htb-test" "ws idempotent: directory intact"
assert_file_exists "$WS_ROOT/e2e-htb-test/.empusa-workspace.json" "ws idempotent: metadata intact"

section "Workspace Select and Status"

set +e
select_out="$($EMPUSA_BIN workspace select --name "e2e-htb-test" --root "$WS_ROOT" 2>&1)"
select_rc=$?
set -e
assert_eq "0" "$select_rc" "ws select: exits 0"

status_out="$($EMPUSA_BIN workspace status --name "e2e-htb-test" --root "$WS_ROOT" 2>&1)" || true
assert_contains "$status_out" "e2e-htb-test" "ws status: shows workspace name"
assert_contains "$status_out" "htb" "ws status: shows profile"

# ═══════════════════════════════════════════════════════════════════
#  5.4  Local contract test suite
# ═══════════════════════════════════════════════════════════════════
section "Empusa Contract Tests"

if [[ ! -x "$LOCAL_PYTHON" ]]; then
    _record_fail "empusa local python" "missing" "$LOCAL_PYTHON"
else
    if [[ ! -d "$LOCAL_EMPUSA_REPO/tests" ]]; then
        _record_fail "empusa local tests dir" "missing" "$LOCAL_EMPUSA_REPO/tests"
    else
        contract_tests=(
            "tests/test_plugins.py"
            "tests/test_bus.py"
            "tests/test_events.py"
            "tests/test_services.py"
            "tests/test_cli_workspace.py"
            "tests/test_workspace_build_e2e.py"
            "tests/test_cli_modules.py"
        )

        for t in "${contract_tests[@]}"; do
            if [[ -f "$LOCAL_EMPUSA_REPO/$t" ]]; then
                _record_pass "contract test file: $t"
            else
                _record_fail "contract test file: $t" "missing" "$LOCAL_EMPUSA_REPO/$t"
            fi
        done

        set +e
        contract_out="$(cd "$LOCAL_EMPUSA_REPO" && "$LOCAL_PYTHON" -m pytest \
            tests/test_plugins.py \
            tests/test_bus.py \
            tests/test_events.py \
            tests/test_services.py \
            tests/test_cli_workspace.py \
            tests/test_workspace_build_e2e.py \
            tests/test_cli_modules.py \
            -q 2>&1)"
        contract_rc=$?
        set -e

        assert_eq "0" "$contract_rc" "empusa contract tests: exits 0"
        if echo "$contract_out" | grep -q "\[100%\]"; then
            _record_pass "empusa contract tests: reached 100% completion"
        else
            _record_fail "empusa contract tests: reached 100% completion" "missing [100%]" "pytest completion marker"
        fi

        if echo "$contract_out" | grep -qi "failed"; then
            _record_fail "empusa contract tests: no failures in output" "contains 'failed'" "all tests passing"
        else
            _record_pass "empusa contract tests: no failures in output"
        fi
    fi
fi

end_stage
