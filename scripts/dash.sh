#!/usr/bin/env bash
# gw dash — a tmux control room for the gateway.
#
#   ┌──────────────────────────┬─────────────────────┐
#   │                          │ status (every 10s)  │
#   │  shell — type `gw ask`   ├─────────────────────┤
#   │                          │ live routing feed   │
#   │                          ├─────────────────────┤
#   │                          │ gateway log         │
#   └──────────────────────────┴─────────────────────┘
#
# Pane IDs (%N) are used throughout rather than indices, because indices depend
# on the user's pane-base-index and silently target the wrong pane otherwise.
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"
S=ai-gateway

if tmux has-session -t "$S" 2>/dev/null; then
  exec tmux attach -t "$S"
fi

# Start the stack first so the panes aren't full of connection errors.
./scripts/db.sh up             >/dev/null 2>&1 || true
./scripts/redis.sh up          >/dev/null 2>&1 || true
./scripts/gateway-ctl.sh start >/dev/null 2>&1 || true

tmux new-session -d -s "$S" -n gateway -c "$ROOT" -x "${TMUX_DASH_COLS:-200}" -y "${TMUX_DASH_ROWS:-50}"
MAIN=$(tmux list-panes -t "$S:gateway" -F '#{pane_id}' | head -1)

STATUS=$(tmux split-window -h -t "$MAIN"   -l 44% -c "$ROOT" -P -F '#{pane_id}')
FEED=$(  tmux split-window -v -t "$STATUS" -l 72% -c "$ROOT" -P -F '#{pane_id}')
LOGS=$(  tmux split-window -v -t "$FEED"   -l 42% -c "$ROOT" -P -F '#{pane_id}')

tmux send-keys -t "$STATUS" "watch -tc -n 10 './scripts/gw status; echo; ./scripts/gw models 2>/dev/null | head -9'" C-m
tmux send-keys -t "$FEED"   "./scripts/feed.sh" C-m
tmux send-keys -t "$LOGS"   "echo '  log — benign noise filtered. gw errors = explained; GW_LOG_VERBOSE=1 = everything'; ./scripts/logfmt.sh" C-m

tmux select-pane -t "$MAIN"
tmux send-keys  -t "$MAIN" "clear; ./scripts/gw; echo; echo 'try:  gw ask \"what is the capital of Finland\"'" C-m

tmux set -t "$S" mouse on
tmux set -t "$S" status-style 'bg=#1a2030,fg=#9aa7bd'
tmux set -t "$S" status-left  '#[bg=#6a74ef,fg=#ffffff,bold] ai-gateway #[default] '
tmux set -t "$S" status-left-length 24
tmux set -t "$S" status-right '#[fg=#6f7d95] copy: shift+drag · detach: C-b d · close: gw dash-kill '
tmux set -t "$S" status-right-length 64
tmux set -t "$S" pane-active-border-style 'fg=#6a74ef'
tmux set -t "$S" pane-border-status top
tmux set -t "$S" pane-border-format ' #{?#{==:#{pane_id},'"$MAIN"'},shell,#{?#{==:#{pane_id},'"$STATUS"'},status,#{?#{==:#{pane_id},'"$FEED"'},routing feed,log}}} '

exec tmux attach -t "$S"
