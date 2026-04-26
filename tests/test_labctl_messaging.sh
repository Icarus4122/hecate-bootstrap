#!/usr/bin/env bash
# tests/test_labctl_messaging.sh
#
# Operator-truthfulness checks against labctl source:
#   - cmd_tmux no-args output describes each profile
#   - cmd_clean warning clarifies bind-mounted LAB_ROOT is not removed
#   - cmd_up emits a [WARN] when --hostnet is used
# These are static-source assertions; they avoid invoking Docker.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "labctl operator messaging"

REPO_DIR="$(dirname "$TESTS_DIR")"
LABCTL="$REPO_DIR/labctl"
assert_file_exists "$LABCTL" "labctl present"

SRC="$(cat "$LABCTL")"

# ── tmux no-args descriptive list ──────────────────────────────────
assert_contains "$SRC" "General operator session"      "tmux: default described"
assert_contains "$SRC" "HTB/CTF workspace session"      "tmux: htb described"
assert_contains "$SRC" "Build/tooling sidecar workflow" "tmux: build described"
assert_contains "$SRC" "Research/notes workflow"        "tmux: research described"

# ── clean warning clarity ──────────────────────────────────────────
assert_contains "$SRC" "Compose-managed containers and named volumes" \
    "clean: identifies what is removed"
assert_contains "$SRC" "bind-mounted runtime data is NOT removed" \
    "clean: clarifies LAB_ROOT bind-mounted data is not removed"

# ── --hostnet WARN ─────────────────────────────────────────────────
assert_contains "$SRC" "Host networking enabled (--hostnet)" \
    "up: warns when --hostnet is set"
assert_contains "$SRC" "share the host network namespace" \
    "up: explains hostnet implication"

# ── End-to-end tmux invocation: bare 'labctl tmux' prints the list ─
make_sandbox
OUT="$SANDBOX/tmux.out"
rc=0
bash "$LABCTL" tmux > "$OUT" 2>&1 || rc=$?
assert_eq "0" "$rc" "labctl tmux (no args): exit 0"
TMUX_OUT="$(cat "$OUT")"
assert_contains "$TMUX_OUT" "Available tmux profiles:" "tmux runtime: header"
assert_contains "$TMUX_OUT" "default"                  "tmux runtime: lists default"
assert_contains "$TMUX_OUT" "research"                 "tmux runtime: lists research"

end_tests
