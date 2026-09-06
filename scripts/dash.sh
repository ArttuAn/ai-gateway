#!/usr/bin/env bash
# gw dash — a tmux control room for the gateway.
#
#   ┌──────────────────────────┬─────────────────────┐
#   │                          │ status (auto)       │
#   │  shell — type `gw ask`   ├─────────────────────┤
#   │                          │ live routing feed   │
#   │                          ├─────────────────────┤
#   │                          │ gateway log         │
#   └──────────────────────────┴─────────────────────┘
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"
S=ai-gateway

# Already running? Just go there.
if tmux has-session -t "$S" 2>/dev/null; then
  exec tmux attach -t "$S"
fi

# Bring the stack up before drawing anything, so the panes aren't full of errors.
./scripts/db.sh up    >/dev/null 2>&1 || true
./scripts/redis.sh up >/dev/null 2>&1 || true
./scripts/gateway-ctl.sh start >/dev/null 2>&1 || true

tmux new-session  -d -s "$S" -n gateway -c "$ROOT" -x "${COLUMNS:-200}" -y "${LINES:-50}"

# left: your shell.  right column: status / feed / logs
tmux split-window -h -t "$S:gateway" -p 44 -c "$ROOT"
tmux split-window -v -t "$S:gateway.1" -p 74 -c "$ROOT"
tmux split-window -v -t "$S:gateway.2" -p 40 -c "$ROOT"

tmux send-keys -t "$S:gateway.1" \
  "watch -tc -n 10 './scripts/gw status; echo; ./scripts/gw models 2>/dev/null | head -9'" C-m
tmux send-keys -t "$S:gateway.2" "./scripts/feed.sh" C-m
tmux send-keys -t "$S:gateway.3" \
  "tail -n 40 -f logs/gateway.log | grep --line-buffered -viE 'liveliness|/metrics'" C-m

tmux select-pane -t "$S:gateway.0"
tmux send-keys -t "$S:gateway.0" "clear; ./scripts/gw" C-m

tmux set -t "$S" mouse on
tmux set -t "$S" status-style 'bg=#1a2030,fg=#9aa7bd'
tmux set -t "$S" status-left  '#[bg=#6a74ef,fg=#ffffff,bold] ai-gateway #[default] '
tmux set -t "$S" status-right '#[fg=#6f7d95]detach: ctrl-b d  ·  quit: gw dash-kill '
tmux set -t "$S" status-left-length 24
tmux set -t "$S" pane-active-border-style 'fg=#6a74ef'

exec tmux attach -t "$S"
