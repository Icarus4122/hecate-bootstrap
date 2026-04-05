#!/usr/bin/env bash
# tmux/profiles/default.sh - General-purpose operator layout.
# Args: <session-name>
# Windows: main, ops
set -euo pipefail

SESSION="${1:-lab}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux attach -t "$SESSION"
    exit 0
fi

tmux new-session -d -s "$SESSION" -n main -c /opt/lab
tmux new-window  -t "$SESSION" -n ops  -c /opt/lab

tmux select-window -t "$SESSION:main"
tmux attach -t "$SESSION"
