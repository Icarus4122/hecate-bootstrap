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
    if grep -q '── Summary' "$src"; then
        _record_pass "style: ${script} has Summary section"
    else
        _record_fail "style: ${script} has Summary section" "missing" "── Summary ──"
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
    if grep -q 'Next steps:' "$src"; then
        _record_pass "style: ${script} has Next steps: label"
    else
        _record_fail "style: ${script} has Next steps: label" "missing" "Next steps:"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  5. Banner format: multi-step scripts open with ╔═══...═══╗
# ═══════════════════════════════════════════════════════════════════
for script in bootstrap-host.sh verify-host.sh update-lab.sh sync-binaries.sh; do
    src="$REPO/scripts/$script"
    if grep -qE '╔═+╗' "$src"; then
        _record_pass "style: ${script} has box banner"
    else
        _record_fail "style: ${script} has box banner" "missing" "╔═══╗ banner"
    fi
done

# labctl (dispatcher) should NOT have a box banner (short commands)
if grep -qE '╔═+╗' "$REPO/labctl"; then
    _record_fail "style: labctl has no box banner" "found banner" "no banner in dispatcher"
else
    _record_pass "style: labctl has no box banner"
fi

# ═══════════════════════════════════════════════════════════════════
#  6. Error messages use [✗] marker
# ═══════════════════════════════════════════════════════════════════

# labctl error messages
labctl_errors="$(grep -c '\[✗\]' "$REPO/labctl" || true)"
if [[ "$labctl_errors" -gt 0 ]]; then
    _record_pass "style: labctl uses [✗] for errors (${labctl_errors} occurrences)"
else
    _record_fail "style: labctl uses [✗] for errors" "0 occurrences" ">0"
fi

# ═══════════════════════════════════════════════════════════════════
#  7. Success messages use [✓] marker
# ═══════════════════════════════════════════════════════════════════
labctl_success="$(grep -c '\[✓\]' "$REPO/labctl" || true)"
if [[ "$labctl_success" -gt 0 ]]; then
    _record_pass "style: labctl uses [✓] for success (${labctl_success} occurrences)"
else
    _record_fail "style: labctl uses [✓] for success" "0 occurrences" ">0"
fi

# ═══════════════════════════════════════════════════════════════════
#  8. Warning messages use [!] marker (not [warn] or WARNING)
# ═══════════════════════════════════════════════════════════════════
for script in labctl scripts/verify-host.sh scripts/launch-lab.sh \
              scripts/create-workspace.sh scripts/sync-binaries.sh; do
    src="$REPO/$script"
    # Check for non-standard warning patterns
    bad_warn="$(grep -nE '\[(warn|WARN|WARNING)\]' "$src" || true)"
    if [[ -z "$bad_warn" ]]; then
        _record_pass "style: $(basename "$script") — no non-standard warning markers"
    else
        _record_fail "style: $(basename "$script") — no non-standard warning markers" \
            "$bad_warn" "use [!] not [warn]/[WARNING]"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  9. Remediation lines use "Fix:" prefix (not "fix:", "FIX:", "To fix:")
# ═══════════════════════════════════════════════════════════════════
for script in scripts/verify-host.sh scripts/create-workspace.sh; do
    src="$REPO/$script"
    if grep -q 'Fix:' "$src"; then
        _record_pass "style: $(basename "$script") uses Fix: prefix"
    else
        _record_fail "style: $(basename "$script") uses Fix: prefix" "missing" "Fix: <command>"
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
#  10. labctl success messages use "Next:" (not "Run:", "Attach:")
# ═══════════════════════════════════════════════════════════════════
# Grep the labctl dispatching functions for old-style success pointers
labctl_src="$(cat "$REPO/labctl")"

bad_pointers="$(echo "$labctl_src" | grep -nE 'echo.*\[✓\].*(Run:|Attach:|Start:)' || true)"
if [[ -z "$bad_pointers" ]]; then
    _record_pass "style: labctl [✓] lines use 'Next:' not Run:/Attach:"
else
    _record_fail "style: labctl [✓] lines use 'Next:' not Run:/Attach:" \
        "$bad_pointers" "Next: only"
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
    # Check that banner() or section headers use ── not --
    if grep -qE 'echo.*"── ' "$src" || grep -qE 'banner\(\).*── ' "$src"; then
        _record_pass "style: $(basename "$script") uses ── headers"
    else
        _record_fail "style: $(basename "$script") uses ── headers" "missing" "── headers"
    fi
done

end_tests
