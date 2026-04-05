#!/usr/bin/env bash
# tmux/profiles/research.sh - Research / learning layout.
# Args: <session-name> [workspace-path]
# Windows: research, notes
set -euo pipefail

SESSION="${1:-research}"
WORKSPACE="${2:-/opt/lab}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux attach -t "$SESSION"
    exit 0
fi

tmux new-session -d -s "$SESSION" -n research -c "$WORKSPACE"
tmux new-window  -t "$SESSION" -n notes    -c "$WORKSPACE"

tmux select-window -t "$SESSION:research"
tmux attach -t "$SESSION"
