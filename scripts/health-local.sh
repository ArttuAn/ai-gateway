#!/usr/bin/env bash
# Free health check — local backend only, no cloud spend.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
if curl -sf -m 3 "$OLLAMA_API_BASE/api/tags" >/dev/null; then
  echo "ollama:  up   ($(curl -s "$OLLAMA_API_BASE/api/tags" | jq -r '[.models[].name]|join(", ")'))"
  echo "loaded:  $(curl -s "$OLLAMA_API_BASE/api/ps" | jq -r 'if (.models|length)==0 then "(none resident)" else [.models[]|"\(.name) until \(.expires_at)"]|join(", ") end')"
else
  echo "ollama:  DOWN"
fi
curl -sf -m 3 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null \
  && echo "gateway: up" || echo "gateway: DOWN"
docker exec "$PG_CONTAINER" pg_isready -U litellm -d litellm >/dev/null 2>&1 \
  && echo "db:      up" || echo "db:      DOWN"
