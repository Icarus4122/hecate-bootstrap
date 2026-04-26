#!/usr/bin/env bash
# tests/test_e2e_harness.sh - Lightweight checks on the e2e harness
# itself (presence, syntax, marker contract).  Does NOT execute the
# stages — it just verifies the harness is well-formed and that the
# canonical marker regex stays canonical.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "e2e harness sanity"

REPO_DIR="$(dirname "$TESTS_DIR")"
E2E_DIR="$REPO_DIR/tests/e2e"

# ── Presence ───────────────────────────────────────────────────────
assert_file_exists "$E2E_DIR/run-validation.sh" "run-validation.sh present"
assert_file_exists "$E2E_DIR/e2e-helpers.sh"    "e2e-helpers.sh present"

if [[ -x "$E2E_DIR/run-validation.sh" ]]; then
    _record_pass "run-validation.sh is executable"
else
    _record_fail "run-validation.sh is executable" "(not +x)" "executable"
fi

# ── Stage scripts: present and syntax-valid ────────────────────────
shopt -s nullglob
stages=( "$E2E_DIR"/stage_*.sh )
shopt -u nullglob

if [[ ${#stages[@]} -ge 7 ]]; then
    _record_pass "e2e: at least 7 stage scripts present (${#stages[@]} found)"
else
    _record_fail "e2e: at least 7 stage scripts present" \
        "${#stages[@]} found" ">= 7"
fi

for s in "${stages[@]}"; do
    name="$(basename "$s")"
    if bash -n "$s" 2>/dev/null; then
        _record_pass "syntax ok: $name"
    else
        _record_fail "syntax ok: $name" "(bash -n failed)" "valid bash"
    fi
done

# ── Scenario scripts: present and syntax-valid ─────────────────────
shopt -s nullglob
scenarios=( "$E2E_DIR"/scenarios/sc_*.sh )
shopt -u nullglob

if [[ ${#scenarios[@]} -gt 0 ]]; then
    _record_pass "e2e: scenario scripts present (${#scenarios[@]} found)"
else
    _record_fail "e2e: scenario scripts present" "0 found" ">= 1"
fi

for sc in "${scenarios[@]}"; do
    name="$(basename "$sc")"
    if bash -n "$sc" 2>/dev/null; then
        _record_pass "syntax ok: $name"
    else
        _record_fail "syntax ok: $name" "(bash -n failed)" "valid bash"
    fi
done

# ── Canonical marker regex: only PASS/FAIL/WARN/INFO/ACTION ────────
# The regex lives in e2e-helpers.sh (assert_structured_output et al).
helpers="$E2E_DIR/e2e-helpers.sh"
marker_re="$(grep -oE '\\\[PASS\\\]\|\\\[FAIL\\\]\|\\\[WARN\\\]\|\\\[INFO\\\]\|\\\[ACTION\\\]' "$helpers" | head -1 || true)"
if [[ -n "$marker_re" ]]; then
    _record_pass "e2e: canonical marker regex present"
else
    _record_fail "e2e: canonical marker regex present" "(not found)" \
        '\\[PASS\\]|\\[FAIL\\]|\\[WARN\\]|\\[INFO\\]|\\[ACTION\\] regex'
fi

# Verify each canonical marker appears in the regex line, and that no
# non-canonical marker (e.g. DEBUG, TRACE, NOTE, ERROR) sneaks in.
for m in PASS FAIL WARN INFO ACTION; do
    if grep -qE "\\\\\\[${m}\\\\\\]" "$helpers"; then
        _record_pass "e2e marker regex includes [$m]"
    else
        _record_fail "e2e marker regex includes [$m]" "(missing)" "in regex"
    fi
done
for forbidden in DEBUG TRACE NOTE ERROR OK; do
    # Look for the forbidden token *inside* a literal-bracket regex.
    if grep -qE "\\\\\\[${forbidden}\\\\\\]" "$helpers"; then
        _record_fail "e2e marker regex excludes [$forbidden]" \
            "(present)" "absent (canonical vocab only)"
    else
        _record_pass "e2e marker regex excludes [$forbidden]"
    fi
done

# ── Stage 5 (Empusa): graceful skip when EMPUSA source missing ─────
# stage_5_empusa.sh must not hard-fail on a missing source tree — it
# should print a "skipping" message and end the stage cleanly.
stage5="$E2E_DIR/stage_5_empusa.sh"
assert_file_exists "$stage5" "stage 5 present"
if grep -qiE "skipping|skip(ped)?" "$stage5"; then
    _record_pass "stage 5: declares skip-on-missing path"
else
    _record_fail "stage 5: declares skip-on-missing path" \
        "(no 'skip' wording)" "skip / skipping wording present"
fi

end_tests
