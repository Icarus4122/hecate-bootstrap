#!/usr/bin/env bash
# tmux/profiles/research.sh - Research / learning layout.
# Usage: research.sh [workspace-o-topic-path]
# Windows: research, notes
set -euo pipefail

WORKSPACE="${1:-/opt/lab/workspaces/research}"
S="research"

tmux has-session -t "$S" 2>/dev/null && { tmux attach -t "$S"; exit 0; }

tmux new-session -d -s "$S" -n research -c "$WORKSPACE"
tmux new-window  -t "$S" -n notes    -c "$WORKSPACE"

tmux select-window -t "$S:research"
tmux attach -t "$S"
