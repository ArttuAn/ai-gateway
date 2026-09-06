#!/usr/bin/env bash
# Start the gateway (daemonised). Logs: logs/gateway.log
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
mkdir -p logs run

# --- preflight -------------------------------------------------------------
# The key used to live only in whatever shell you had exported it in, which
# meant the gateway could not survive a reboot and a desktop launcher could
# never start it. It now lives in one chmod-600 file outside the repo.
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -r "$HOME/.config/ai-gateway/secrets.env" ]; then
  set -a; source "$HOME/.config/ai-gateway/secrets.env"; set +a
fi
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY not set and ~/.config/ai-gateway/secrets.env missing — the cloud tier cannot start}"

if ! curl -sf -m 3 "$OLLAMA_API_BASE/api/tags" >/dev/null; then
  echo "!! Ollama is not answering on $OLLAMA_API_BASE — local tiers will fail over to cloud." >&2
  echo "   start it with:  ollama serve" >&2
fi

docker exec "$PG_CONTAINER" pg_isready -U litellm -d litellm >/dev/null 2>&1 \
  || { echo "postgres is down — run: scripts/db.sh up" >&2; exit 1; }

if [ -f run/gateway.pid ] && kill -0 "$(cat run/gateway.pid)" 2>/dev/null; then
  echo "gateway already running (pid $(cat run/gateway.pid))"; exit 0
fi

# --- launch ----------------------------------------------------------------
nohup .venv/bin/litellm \
  --config config/config.yaml \
  --host "$GATEWAY_HOST" --port "$GATEWAY_PORT" \
  >> logs/gateway.log 2>&1 &
echo $! > run/gateway.pid

printf 'starting gateway'
for i in $(seq 1 90); do
  if curl -sf -m 2 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null 2>&1; then
    echo " → http://$GATEWAY_HOST:$GATEWAY_PORT   (UI: /ui, docs: /docs)"; exit 0
  fi
  kill -0 "$(cat run/gateway.pid)" 2>/dev/null || { echo; echo "gateway died on boot — last log lines:" >&2; tail -25 logs/gateway.log >&2; exit 1; }
  printf '.'; sleep 1
done
echo; echo "gateway not healthy after 90s; see logs/gateway.log" >&2; exit 1
