#!/usr/bin/env bash
# Redis: shared rate-limit + spend-buffer state across LiteLLM workers.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
case "${1:-up}" in
  up)
    if docker ps -a --format '{{.Names}}' | grep -qx "$REDIS_CONTAINER"; then
      docker start "$REDIS_CONTAINER" >/dev/null
    else
      docker run -d --name "$REDIS_CONTAINER" \
        -p 127.0.0.1:"$REDIS_PORT":6379 \
        -v ai-gateway-redis:/data \
        --restart unless-stopped \
        redis:7-alpine redis-server \
          --requirepass "$REDIS_PASSWORD" \
          --appendonly yes \
          --maxmemory 256mb \
          --maxmemory-policy allkeys-lru >/dev/null
    fi
    for i in $(seq 1 30); do
      docker exec "$REDIS_CONTAINER" redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping 2>/dev/null | grep -q PONG \
        && { echo "redis ready on 127.0.0.1:$REDIS_PORT"; exit 0; }
      sleep 1
    done
    echo "redis did not become ready; docker logs $REDIS_CONTAINER" >&2; exit 1 ;;
  down)    docker stop "$REDIS_CONTAINER" >/dev/null && echo "redis stopped" ;;
  destroy) docker rm -f "$REDIS_CONTAINER" >/dev/null 2>&1 || true
           docker volume rm ai-gateway-redis >/dev/null 2>&1 || true; echo "redis removed" ;;
  *) echo "usage: $0 {up|down|destroy}" >&2; exit 2 ;;
esac
