#!/usr/bin/env bash
# tmux/profiles/default.sh — General-purpose operator layout.
# Windows: main, ops
set -euo pipefail

S="default"

tmux has-session -t "$S" 2>/dev/null && { tmux attach -t "$S"; exit 0; }

tmux new-session -d -s "$S" -n main -c /opt/lab
tmux new-window  -t "$S" -n ops  -c /opt/lab

tmux select-window -t "$S:main"
tmux attach -t "$S"
