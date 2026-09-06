#!/usr/bin/env bash
# One-click launcher: bring the whole stack up, then open the interfaces.
#
# Runs from a desktop icon, which means NO shell environment and NO terminal to
# print errors into — so every step reports through desktop notifications and
# failures surface in a dialog instead of vanishing.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
ICON="$DIR/assets/ai-gateway.svg"
LOG="$DIR/logs/launch.log"
mkdir -p logs
exec 2>>"$LOG"
echo "=== launch $(date -Iseconds) ===" >>"$LOG"

# What to open. Override in ~/.config/ai-gateway/launch.conf
OPEN_CHAT=1; OPEN_ADMIN=1; OPEN_EDITOR=1
[ -r "$HOME/.config/ai-gateway/launch.conf" ] && source "$HOME/.config/ai-gateway/launch.conf"

set -a; source .env; set +a

NID=""
status() {
  echo "[status] $1" >>"$LOG"
  if [ -n "$NID" ]; then
    notify-send -a "AI Gateway" -r "$NID" -i "$ICON" "AI Gateway" "$1" 2>/dev/null || true
  else
    NID=$(notify-send -a "AI Gateway" -p -i "$ICON" "AI Gateway" "$1" 2>/dev/null) || NID=""
  fi
}
die() {
  echo "[fail] $1" >>"$LOG"
  notify-send -a "AI Gateway" -u critical -i "$ICON" "AI Gateway failed" "$1" 2>/dev/null || true
  zenity --error --title="AI Gateway" --width=460 \
    --text="$1

Last lines of the log:
$(tail -n 12 "$LOG" | sed 's/&/\&amp;/g; s/</\&lt;/g')" 2>/dev/null || true
  exit 1
}

# ── stop mode (right-click → Stop everything) ────────────────────────────────
if [ "${1:-}" = "--stop" ]; then
  ./scripts/webui.sh down >>"$LOG" 2>&1 || true
  ./scripts/gateway-ctl.sh stop >>"$LOG" 2>&1 || true
  ./scripts/db.sh down    >>"$LOG" 2>&1 || true
  notify-send -a "AI Gateway" -i "$ICON" "AI Gateway" "Stopped. Local models stay loaded in Ollama." 2>/dev/null || true
  exit 0
fi

# ── bring the stack up (each step is idempotent) ─────────────────────────────
status "Starting local model server…"
systemctl --user start ollama >>"$LOG" 2>&1 || true
curl -sf -m 5 "$OLLAMA_API_BASE/api/tags" >/dev/null 2>&1 \
  || status "Ollama unavailable — routine work will fail over to cloud."

status "Starting database…"
./scripts/db.sh up >>"$LOG" 2>&1 || die "Could not start Postgres. Is Docker running?"
./scripts/redis.sh up >>"$LOG" 2>&1 || die "Could not start Redis."

status "Starting gateway…"
./scripts/gateway-ctl.sh start >>"$LOG" 2>&1 || die "The gateway did not come up. See logs/gateway.log"

# Open WebUI is optional and not installed by default (it cost 8GB and went
# unused). Only start it if its image is actually present.
if docker image inspect ghcr.io/open-webui/open-webui:main >/dev/null 2>&1; then
  status "Starting chat UI…"
  ./scripts/webui.sh up >>"$LOG" 2>&1 || die "Open WebUI did not come up. Try: docker logs open-webui"
  OPEN_CHAT_AVAILABLE=1
else
  OPEN_CHAT_AVAILABLE=0
fi

# ── open the interfaces ──────────────────────────────────────────────────────
status "Opening interfaces…"
[ "$OPEN_CHAT" = 1 ] && [ "$OPEN_CHAT_AVAILABLE" = 1 ] && xdg-open "http://127.0.0.1:${WEBUI_PORT:-3000}" >>"$LOG" 2>&1 &
sleep 1
[ "$OPEN_ADMIN" = 1 ] && xdg-open "http://$GATEWAY_HOST:$GATEWAY_PORT/ui"     >>"$LOG" 2>&1 &
[ "$OPEN_EDITOR" = 1 ] && command -v code >/dev/null && code "$DIR"           >>"$LOG" 2>&1 &

status "Ready — chat :${WEBUI_PORT:-3000} · admin :$GATEWAY_PORT/ui"
exit 0
