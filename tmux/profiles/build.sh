#!/usr/bin/env bash
# tmux/profiles/build.sh - Builder / compilation layout.
# Args: <session-name> [workspace-path]
# Windows: build, tools
set -euo pipefail

SESSION="${1:-build}"
WORKSPACE="${2:-/opt/lab/tools}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux attach -t "$SESSION"
    exit 0
fi

tmux new-session -d -s "$SESSION" -n build -c "$WORKSPACE"
tmux new-window  -t "$SESSION" -n tools -c "$WORKSPACE"

tmux select-window -t "$SESSION:build"
tmux attach -t "$SESSION"
