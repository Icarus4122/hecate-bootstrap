#!/usr/bin/env bash
# tmux/profiles/htb.sh - Hack The Box focused layout.
# Args: <session-name> <workspace-path>
# Windows: main, ops - both cd into the workspace.
set -euo pipefail

SESSION="${1:?Session name required}"
WORKSPACE="${2:?Workspace path required}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux attach -t "$SESSION"
    exit 0
fi

tmux new-session -d -s "$SESSION" -n main -c "$WORKSPACE"
tmux new-window  -t "$SESSION" -n ops  -c "$WORKSPACE"

tmux select-window -t "$SESSION:main"
tmux attach -t "$SESSION"
