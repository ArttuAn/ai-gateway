#!/usr/bin/env bash
# Open WebUI — the graphical chat front-end for the gateway.
#
# Runs with --network host on purpose: the gateway listens on 127.0.0.1 only,
# and a bridged container cannot reach the host's loopback. Sharing the host
# netns is what lets the container talk to 127.0.0.1:4000 without exposing the
# gateway on a routable interface.
#
# HOST=127.0.0.1 then keeps Open WebUI itself on loopback too — without it,
# --network host means it binds 0.0.0.0 and your whole LAN gets a chat UI
# wired to your paid API key.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; source keys.env; set +a
NAME=open-webui
PORT="${WEBUI_PORT:-3000}"

case "${1:-up}" in
  up)
    if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
      docker start "$NAME" >/dev/null
    else
      docker run -d --name "$NAME" \
        --network host \
        -e HOST=127.0.0.1 \
        -e PORT="$PORT" \
        -e OPENAI_API_BASE_URL="http://127.0.0.1:$GATEWAY_PORT/v1" \
        -e OPENAI_API_KEY="$CHAT_UI_KEY" \
        -e ENABLE_OLLAMA_API=false \
        -e WEBUI_NAME="AI Gateway" \
        -e ANONYMIZED_TELEMETRY=false \
        -e DO_NOT_TRACK=true \
        -e SCARF_NO_ANALYTICS=true \
        -v open-webui:/app/backend/data \
        --restart unless-stopped \
        ghcr.io/open-webui/open-webui:main >/dev/null
    fi
    printf 'waiting for open-webui'
    for i in $(seq 1 120); do
      if curl -sf -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        echo " → http://127.0.0.1:$PORT"
        echo "   first visit: create the local admin account (stays on this machine)"
        exit 0
      fi
      printf '.'; sleep 2
    done
    echo; echo "not healthy yet — docker logs $NAME" >&2; exit 1 ;;
  down)    docker stop "$NAME" >/dev/null && echo "open-webui stopped" ;;
  logs)    docker logs -f "$NAME" ;;
  destroy) docker rm -f "$NAME" >/dev/null 2>&1 || true
           docker volume rm open-webui >/dev/null 2>&1 || true
           echo "open-webui + its data volume removed" ;;
  *) echo "usage: $0 {up|down|logs|destroy}" >&2; exit 2 ;;
esac
