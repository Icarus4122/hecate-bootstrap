#!/usr/bin/env bash
# tests/e2e/stage_7_ux.sh - UX and output validation.
#
# No Docker, no root.  Validates: labctl output quality, help system,
# error messages, style guide compliance, Empusa CLI output.
#
# This augments the existing test_labctl_ux.sh and test_output_style.sh
# unit tests with full-integration validation that runs labctl directly.

begin_stage 7 "UX & Output"

# ═══════════════════════════════════════════════════════════════════
#  7.1  labctl help system
# ═══════════════════════════════════════════════════════════════════
section "Help System"

help_out="$(bash "$REPO_ROOT/labctl" help 2>&1)" || true
help_rc=$?
assert_eq "0" "$help_rc" "help: exits 0"

# Structural sections
for heading in "GETTING STARTED" "DAILY WORKFLOW" "COMMANDS" "EXAMPLES" \
               "TROUBLESHOOTING" "ENVIRONMENT"; do
    assert_contains "$help_out" "$heading" "help: has $heading section"
done

# All subcommands listed
for cmd in up down build shell sync launch workspace status \
           bootstrap verify update clean guide help version; do
    if echo "$help_out" | grep -qw "$cmd"; then
        _record_pass "help: lists command '$cmd'"
    else
        _record_fail "help: lists command '$cmd'" "not found" "in help output"
    fi
done

# Copy-pasteable examples
for example in "labctl launch htb" "labctl up" "labctl sync"; do
    if echo "$help_out" | grep -qF "$example"; then
        _record_pass "help: example '$example'"
    else
        _record_fail "help: example '$example'" "not found" "in examples"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  7.2  Per-command help
# ═══════════════════════════════════════════════════════════════════
section "Per-Command Help"

for cmd in up down build launch workspace sync tmux status verify \
           update bootstrap clean version guide; do
    cmd_help_out="$(bash "$REPO_ROOT/labctl" help "$cmd" 2>&1)" || true
    cmd_help_rc=$?
    assert_eq "0" "$cmd_help_rc" "help $cmd: exits 0"
    assert_contains "$cmd_help_out" "labctl $cmd" "help $cmd: contains 'labctl $cmd'"
done

# ═══════════════════════════════════════════════════════════════════
#  7.3  -h and --help aliases
# ═══════════════════════════════════════════════════════════════════
section "Help Aliases"

for flag in -h --help; do
    alias_out="$(bash "$REPO_ROOT/labctl" "$flag" 2>&1)" || true
    alias_rc=$?
    assert_eq "0" "$alias_rc" "labctl $flag: exits 0"
    assert_contains "$alias_out" "COMMANDS" "labctl $flag: shows help"
done

# ═══════════════════════════════════════════════════════════════════
#  7.4  Error messages
# ═══════════════════════════════════════════════════════════════════
section "Error Messages"

# Unknown command
set +e
unk_out="$(bash "$REPO_ROOT/labctl" nonexistent-cmd 2>&1)"
unk_rc=$?
set -e
assert_eq "1" "$unk_rc" "unknown cmd: exits 1"
assert_contains "$unk_out" "Unknown command" "unknown cmd: says 'Unknown command'"
assert_contains "$unk_out" "labctl help" "unknown cmd: points to help"

# Bad help topic
set +e
bad_help_out="$(bash "$REPO_ROOT/labctl" help nonexistent-topic 2>&1)"
bad_help_rc=$?
set -e
assert_eq "1" "$bad_help_rc" "bad help topic: exits 1"

# ═══════════════════════════════════════════════════════════════════
#  7.5  labctl version
# ═══════════════════════════════════════════════════════════════════
section "Version"

ver_out="$(bash "$REPO_ROOT/labctl" version 2>&1)" || true
ver_rc=$?
assert_eq "0" "$ver_rc" "version: exits 0"
assert_contains "$ver_out" "labctl" "version: contains 'labctl'"

# ═══════════════════════════════════════════════════════════════════
#  7.6  Output style guide compliance (static analysis)
# ═══════════════════════════════════════════════════════════════════
section "Style Guide Compliance"

# labctl: errors use ui_fail / ui_error_block (canonical [FAIL])
labctl_errors="$(grep -cE 'ui_fail|ui_error_block' "$REPO_ROOT/labctl" || echo 0)"
if [[ "$labctl_errors" -gt 0 ]]; then
    _record_pass "style: labctl uses ui_fail/ui_error_block ($labctl_errors)"
else
    _record_fail "style: labctl uses ui_fail" "0" ">0"
fi

# labctl: success uses ui_pass (canonical [PASS])
labctl_success="$(grep -c 'ui_pass' "$REPO_ROOT/labctl" || echo 0)"
if [[ "$labctl_success" -gt 0 ]]; then
    _record_pass "style: labctl uses ui_pass ($labctl_success)"
else
    _record_fail "style: labctl uses ui_pass" "0" ">0"
fi

# Multi-step scripts have banners (inline ╔═══╗ OR ui_banner call)
for script in scripts/bootstrap-host.sh scripts/verify-host.sh \
              scripts/update-lab.sh scripts/sync-binaries.sh; do
    if grep -qE '╔═+╗|ui_banner' "$REPO_ROOT/$script"; then
        _record_pass "style: $(basename $script) has box banner"
    else
        _record_fail "style: $(basename $script) box banner" "missing" "╔═══╗ or ui_banner"
    fi
done

# Multi-step scripts have Summary + Result
for script in scripts/bootstrap-host.sh scripts/verify-host.sh \
              scripts/update-lab.sh scripts/sync-binaries.sh; do
    base="$(basename "$script")"
    if grep -qE '── Summary|ui_summary_line' "$REPO_ROOT/$script"; then
        _record_pass "style: $base has Summary section"
    else
        _record_fail "style: $base Summary" "missing" "── Summary or ui_summary_line"
    fi
    if grep -q 'Result:' "$REPO_ROOT/$script"; then
        _record_pass "style: $base has Result: label"
    else
        _record_fail "style: $base Result:" "missing" "Result:"
    fi
done

# No non-standard warning markers (canonical is [WARN] via ui_warn)
for script in labctl scripts/verify-host.sh scripts/launch-lab.sh; do
    if grep -qE '\[(warn|WARNING)\]' "$REPO_ROOT/$script"; then
        _record_fail "style: $(basename $script) bad warning markers" \
            "found [warn]/[WARNING]" "use ui_warn / [WARN]"
    else
        _record_pass "style: $(basename $script) uses standard [WARN] warnings"
    fi
done

# No old-style success pointers (Run:/Attach: instead of [ACTION] Next)
bad_pointers="$(grep -nE 'echo.*(Run:|Attach:|Start:)' "$REPO_ROOT/labctl" | grep -vE 'ui_action|\[ACTION\]' || true)"
if [[ -z "$bad_pointers" ]]; then
    _record_pass "style: labctl uses [ACTION] not Run:/Attach:"
else
    _record_fail "style: labctl action pointers" "$bad_pointers" "[ACTION] only"
fi

# ═══════════════════════════════════════════════════════════════════
#  7.7  Empusa CLI output (conditional)
# ═══════════════════════════════════════════════════════════════════
section "Empusa CLI Output"

EMPUSA_BIN="${LAB_ROOT:-/opt/lab}/tools/venvs/empusa/bin/empusa"

if [[ -x "$EMPUSA_BIN" ]]; then
    # empusa --help should list subcommands
    e_help="$("$EMPUSA_BIN" --help 2>&1)" || true
    assert_contains "$e_help" "workspace" "empusa help: lists workspace"
    assert_contains "$e_help" "build" "empusa help: lists build"
    assert_contains "$e_help" "loot" "empusa help: lists loot"
    assert_contains "$e_help" "report" "empusa help: lists report"
    assert_contains "$e_help" "plugins" "empusa help: lists plugins"

    # empusa workspace --help
    e_ws_help="$("$EMPUSA_BIN" workspace --help 2>&1)" || true
    for subcmd in init list select status; do
        assert_contains "$e_ws_help" "$subcmd" "empusa workspace help: lists $subcmd"
    done
else
    _record_pass "Empusa not installed — skip CLI output tests"
fi

# ═══════════════════════════════════════════════════════════════════
#  7.8  Documentation file alignment
# ═══════════════════════════════════════════════════════════════════
section "Documentation Alignment"

# README.md should exist and mention labctl
if [[ -f "$REPO_ROOT/README.md" ]]; then
    assert_file_contains "$REPO_ROOT/README.md" "labctl" "README: mentions labctl"
else
    _record_fail "README.md exists" "missing" "README.md"
fi

# docs/labctl.md should cover all subcommands
if [[ -f "$REPO_ROOT/docs/labctl.md" ]]; then
    labctl_doc="$(cat "$REPO_ROOT/docs/labctl.md")"
    for cmd in up down build launch workspace sync tmux status verify \
               update bootstrap clean; do
        if echo "$labctl_doc" | grep -qw "$cmd"; then
            _record_pass "docs/labctl.md: documents '$cmd'"
        else
            _record_fail "docs/labctl.md: documents '$cmd'" "missing" "in docs"
        fi
    done
else
    _record_fail "docs/labctl.md exists" "missing" "docs/labctl.md"
fi

# Output style guide should exist
assert_file_exists "$REPO_ROOT/docs/dev/output-style-guide.md" \
    "docs: output-style-guide.md exists"

end_stage
