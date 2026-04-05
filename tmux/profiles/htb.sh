#!/usr/bin/env bash
# tmux/profiles/htb.sh — Hack The Box focused layout.
# Usage: htb.sh <workspace-path>
# Windows: main, ops — both cd into the workspace.
set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: htb.sh <workspace-path>" >&2
    echo "  e.g. htb.sh /opt/lab/workspaces/boxes/mybox" >&2
    exit 1
fi

WORKSPACE="$1"
S="htb-$(basename "$WORKSPACE")"

tmux has-session -t "$S" 2>/dev/null && { tmux attach -t "$S"; exit 0; }

tmux new-session -d -s "$S" -n main -c "$WORKSPACE"
tmux new-window  -t "$S" -n ops  -c "$WORKSPACE"

tmux select-window -t "$S:main"
tmux attach -t "$S"
