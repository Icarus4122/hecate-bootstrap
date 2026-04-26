#!/usr/bin/env bash
# tests/test_docs_commands.sh - Verify that key commands documented in
# README.md, docs/, and labctl help map to real labctl subcommands or
# real script files.  Catches drift where docs reference a command that
# was renamed or deleted.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "docs ↔ command mapping"

REPO_DIR="$(dirname "$TESTS_DIR")"
LABCTL="$REPO_DIR/labctl"

# Build a single haystack of "documentation surfaces" so a command
# documented anywhere in README/docs/labctl-help counts as documented.
DOCS_HAYSTACK="$(
    {
        cat "$REPO_DIR/README.md" 2>/dev/null || true
        find "$REPO_DIR/docs" -type f -name '*.md' -print0 2>/dev/null \
            | xargs -0 cat 2>/dev/null || true
        cat "$LABCTL" 2>/dev/null || true
    }
)"

# ── Each documented labctl subcommand must have a cmd_* function ───
# Parse the dispatch table line in labctl to extract the canonical list.
dispatch_line="$(grep -E '^\s*up\|down\|build\|' "$LABCTL" | head -1 || true)"
if [[ -z "$dispatch_line" ]]; then
    _record_fail "labctl: dispatch table parsed" "(no up|down|... line)" \
        "labctl has a 'up|down|build|...' case branch"
else
    _record_pass "labctl: dispatch table parsed"
fi

KEY_COMMANDS=(up down shell verify status update launch workspace sync clean)

for cmd in "${KEY_COMMANDS[@]}"; do
    # 1. Must appear in docs/help somewhere
    if grep -qE "labctl[[:space:]]+$cmd([[:space:]]|$)" <<< "$DOCS_HAYSTACK"; then
        _record_pass "docs: 'labctl $cmd' documented"
    else
        _record_fail "docs: 'labctl $cmd' documented" \
            "(no mention of 'labctl $cmd')" "documented in README/docs/help"
    fi

    # 2. Must have a corresponding cmd_<x> function in labctl
    if grep -qE "^cmd_${cmd}\(\)" "$LABCTL"; then
        _record_pass "labctl: cmd_${cmd}() defined"
    else
        _record_fail "labctl: cmd_${cmd}() defined" "(missing)" "function defined"
    fi

    # 3. Must appear in the dispatch case branch
    if echo "$dispatch_line" | grep -qE "(\\||^)\s*${cmd}(\\||\\))"; then
        _record_pass "labctl: dispatch handles '${cmd}'"
    else
        _record_fail "labctl: dispatch handles '${cmd}'" \
            "(missing in case)" "in up|down|... case branch"
    fi
done

# ── workspace/create wording: docs may use either form ─────────────
if grep -qE "labctl[[:space:]]+workspace" <<< "$DOCS_HAYSTACK"; then
    _record_pass "docs: 'labctl workspace' (or workspace/create) referenced"
else
    _record_fail "docs: 'labctl workspace' referenced" \
        "(absent)" "documented"
fi

# ── External harness reference ─────────────────────────────────────
if grep -qE "tests/e2e/run-validation\.sh" <<< "$DOCS_HAYSTACK"; then
    _record_pass "docs: tests/e2e/run-validation.sh referenced"
else
    _record_fail "docs: tests/e2e/run-validation.sh referenced" \
        "(absent)" "documented"
fi
assert_file_exists "$REPO_DIR/tests/e2e/run-validation.sh" \
    "tests/e2e/run-validation.sh exists on disk"

# ── Sub-script files behind labctl exist on disk ───────────────────
for f in scripts/verify-host.sh scripts/update-lab.sh \
         scripts/create-workspace.sh scripts/launch-lab.sh \
         scripts/sync-binaries.sh scripts/bootstrap-host.sh; do
    assert_file_exists "$REPO_DIR/$f" "backing script exists: $f"
done

end_tests
