#!/usr/bin/env bash
# tests/test_output_style.sh - Cross-script output style consistency.
#
# Validates that all operator-facing scripts follow the output style guide
# (docs/dev/output-style-guide.md).  Tests are grep/pattern-based — they
# check structural properties of output helpers, not exact wording.
#
# What this catches:
#   - Missing or malformed status markers (must use [✓] [✗] [!] [*] [=])
#   - Inconsistent helper naming across scripts
#   - Missing summary/result blocks in multi-step scripts
#   - Missing "Next steps" or "Fix:" remediation patterns
#   - Banner format drift
#
# Strategy: read the script source files as text and check for patterns.
# This avoids executing scripts (which need Docker, root, etc.) while
# still catching style regressions from edits.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "output style consistency"

REPO="$(dirname "$TESTS_DIR")"

# ═══════════════════════════════════════════════════════════════════
#  1. Status marker vocabulary: scripts use bracketed tokens
#     Reject bare ✓/✗ in echo statements (summary counters exempt)
# ═══════════════════════════════════════════════════════════════════

# Check each script for bare (unbracketed) ✓ or ✗ in echo/printf.
# Allowed: inside summary counter lines (printf "  ✓ %d passed")
# Allowed: inside printf for summary reprint (printf "    ✗ %s")
# Forbidden: echo "    ✓ Downloaded" (should be [✓])
_check_bare_markers() {
    local file="$1" label="$2"
    # Find echo lines with bare ✓/✗ that aren't inside summary counter format
    # or the summary reprint loop.  We grep for the pattern, then exclude
    # known-good summary lines.
    local violations
    violations="$(grep -nE 'echo.*"[[:space:]]+(✓|✗)[[:space:]]' "$file" \
        | grep -vE '%d passed|%s\\n.*\$msg|_record_' || true)"
    if [[ -z "$violations" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$violations" "no bare ✓/✗ in echo"
    fi
}

_check_bare_markers "$REPO/scripts/bootstrap-host.sh" "style: bootstrap — no bare markers"
_check_bare_markers "$REPO/scripts/sync-binaries.sh"  "style: sync — no bare markers"
_check_bare_markers "$REPO/scripts/launch-lab.sh"     "style: launch — no bare markers"
_check_bare_markers "$REPO/scripts/update-lab.sh"     "style: update — no bare markers"
_check_bare_markers "$REPO/scripts/create-workspace.sh" "style: workspace — no bare markers"

# ═══════════════════════════════════════════════════════════════════
#  2. Multi-step scripts have a Summary section
# ═══════════════════════════════════════════════════════════════════
for script in bootstrap-host.sh verify-host.sh update-lab.sh sync-binaries.sh; do
    src="$REPO/scripts/$script"
    if grep -qE '── Summary|ui_summary_line' "$src"; then
        _record_pass "style: ${script} has Summary section"
    else
        _record_fail "style: ${script} has Summary section" "missing" "── Summary ── or ui_summary_line"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  3. Multi-step scripts have a "Result:" line in summary
# ═══════════════════════════════════════════════════════════════════
for script in bootstrap-host.sh verify-host.sh update-lab.sh sync-binaries.sh; do
    src="$REPO/scripts/$script"
    if grep -q 'Result:' "$src"; then
        _record_pass "style: ${script} has Result: label"
    else
        _record_fail "style: ${script} has Result: label" "missing" "Result:"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  4. Scripts with next-step guidance use "Next steps:" label
# ═══════════════════════════════════════════════════════════════════
for script in bootstrap-host.sh verify-host.sh; do
    src="$REPO/scripts/$script"
    if grep -qE 'Next steps:|ui_next_block' "$src"; then
        _record_pass "style: ${script} has Next steps: label"
    else
        _record_fail "style: ${script} has Next steps: label" "missing" "Next steps: or ui_next_block"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  5. Banner format: multi-step scripts open with ╔═══...═══╗
# ═══════════════════════════════════════════════════════════════════
for script in bootstrap-host.sh verify-host.sh update-lab.sh sync-binaries.sh; do
    src="$REPO/scripts/$script"
    if grep -qE '╔═+╗|ui_banner' "$src"; then
        _record_pass "style: ${script} has box banner"
    else
        _record_fail "style: ${script} has box banner" "missing" "╔═══╗ or ui_banner"
    fi
done

# labctl uses ui.sh (shared primitives) which should NOT have a standalone box banner.
# However cmd_status now calls ui_banner, which is correct for major surfaces.
# The rule is: no INLINE box banner echoed in labctl itself.
if grep -qE '^echo.*╔═+╗' "$REPO/labctl"; then
    _record_fail "style: labctl has no inline box banner" "found banner" "use ui_banner from lib/ui.sh"
else
    _record_pass "style: labctl has no inline box banner"
fi

# ═══════════════════════════════════════════════════════════════════
#  6. Error messages use [FAIL] marker (via ui_fail from lib/ui.sh)
# ═══════════════════════════════════════════════════════════════════

# labctl delegates to ui_fail/ui_error_block
labctl_errors="$(grep -cE 'ui_fail|ui_error_block' "$REPO/labctl" || true)"
if [[ "$labctl_errors" -gt 0 ]]; then
    _record_pass "style: labctl uses ui_fail for errors (${labctl_errors} call sites)"
else
    _record_fail "style: labctl uses ui_fail for errors" "0 call sites" ">0"
fi

# Verify ui.sh itself emits [FAIL]
if grep -q '\[FAIL\]' "$REPO/scripts/lib/ui.sh"; then
    _record_pass "style: lib/ui.sh defines [FAIL] marker"
else
    _record_fail "style: lib/ui.sh defines [FAIL] marker" "missing" "[FAIL]"
fi

# ═══════════════════════════════════════════════════════════════════
#  7. Success messages use [PASS] marker (via ui_pass from lib/ui.sh)
# ═══════════════════════════════════════════════════════════════════
labctl_success="$(grep -c 'ui_pass' "$REPO/labctl" || true)"
if [[ "$labctl_success" -gt 0 ]]; then
    _record_pass "style: labctl uses ui_pass for success (${labctl_success} call sites)"
else
    _record_fail "style: labctl uses ui_pass for success" "0 call sites" ">0"
fi

if grep -q '\[PASS\]' "$REPO/scripts/lib/ui.sh"; then
    _record_pass "style: lib/ui.sh defines [PASS] marker"
else
    _record_fail "style: lib/ui.sh defines [PASS] marker" "missing" "[PASS]"
fi

# ═══════════════════════════════════════════════════════════════════
#  8. Warning messages use [WARN] marker (via ui_warn from lib/ui.sh)
#     Also ensure no non-standard [warn]/[WARNING] patterns
# ═══════════════════════════════════════════════════════════════════
for script in labctl scripts/verify-host.sh scripts/launch-lab.sh \
              scripts/create-workspace.sh scripts/sync-binaries.sh; do
    src="$REPO/$script"
    # Check for non-standard warning patterns
    bad_warn="$(grep -nE '\[(warn|WARNING)\]' "$src" || true)"
    if [[ -z "$bad_warn" ]]; then
        _record_pass "style: $(basename "$script") — no non-standard warning markers"
    else
        _record_fail "style: $(basename "$script") — no non-standard warning markers" \
            "$bad_warn" "use ui_warn ([WARN]) not [warn]/[WARNING]"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  9. Remediation lines use "Fix:" prefix (not "fix:", "FIX:", "To fix:")
# ═══════════════════════════════════════════════════════════════════
for script in scripts/verify-host.sh scripts/create-workspace.sh; do
    src="$REPO/$script"
    if grep -qE 'Fix:|ui_fix' "$src"; then
        _record_pass "style: $(basename "$script") uses Fix: prefix"
    else
        _record_fail "style: $(basename "$script") uses Fix: prefix" "missing" "Fix: or ui_fix"
    fi
    # Check no variant spellings
    bad_fix="$(grep -nE '^\s+(fix:|FIX:|To fix:)' "$src" || true)"
    if [[ -z "$bad_fix" ]]; then
        _record_pass "style: $(basename "$script") — no variant Fix: spellings"
    else
        _record_fail "style: $(basename "$script") — no variant Fix: spellings" \
            "$bad_fix" "Fix: only"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  10. labctl success calls use ui_pass/ui_next_block (not "Next:"/"Run:")
# ═══════════════════════════════════════════════════════════════════
# Ensure no old-style inline success messages with bare Run:/Attach:
labctl_src="$(cat "$REPO/labctl")"

bad_pointers="$(echo "$labctl_src" | grep -nE 'echo.*\[(PASS|✓)\].*(Run:|Attach:|Start:)' || true)"
if [[ -z "$bad_pointers" ]]; then
    _record_pass "style: labctl success lines use ui_next_block not Run:/Attach:"
else
    _record_fail "style: labctl success lines use ui_next_block not Run:/Attach:" \
        "$bad_pointers" "ui_next_block only"
fi

# ═══════════════════════════════════════════════════════════════════
#  11. create-workspace.sh: no [fallback] or [empusa] prefixes
#      (should use standard vocabulary)
# ═══════════════════════════════════════════════════════════════════
ws_src="$(cat "$REPO/scripts/create-workspace.sh")"
for prefix in "[fallback]" "[empusa]"; do
    if echo "$ws_src" | grep -qF "$prefix"; then
        _record_fail "style: create-workspace — no ${prefix} prefix" "found" "standard markers"
    else
        _record_pass "style: create-workspace — no ${prefix} prefix"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  12. Section headers use ── (em-dash) not -- (hyphens)
# ═══════════════════════════════════════════════════════════════════
for script in scripts/bootstrap-host.sh scripts/verify-host.sh \
              scripts/update-lab.sh scripts/launch-lab.sh; do
    src="$REPO/$script"
    # Check that banner() or section headers use ── not -- (ui_section/ui_banner is also valid)
    if grep -qE 'echo.*"── |ui_section|ui_summary_line|ui_banner' "$src"; then
        _record_pass "style: $(basename "$script") uses ── headers"
    else
        _record_fail "style: $(basename "$script") uses ── headers" "missing" "── headers or ui_section"
    fi
done

end_tests
