#!/usr/bin/env bash
# tmux/profiles/build.sh - Builder / compilation layout.
# Usage: build.sh [workspace-path]
# Windows: build, tools
set -euo pipefail

WORKSPACE="${1:-/opt/lab/tools}"
S="build"

tmux has-session -t "$S" 2>/dev/null && { tmux attach -t "$S"; exit 0; }

tmux new-session -d -s "$S" -n build -c "$WORKSPACE"
tmux new-window  -t "$S" -n tools -c "$WORKSPACE"

tmux select-window -t "$S:build"
tmux attach -t "$S"
