#!/usr/bin/env bash
# Postgres for the gateway's spend ledger, virtual keys and budgets.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

case "${1:-up}" in
  up)
    if docker ps -a --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
      docker start "$PG_CONTAINER" >/dev/null
    else
      docker run -d --name "$PG_CONTAINER" \
        -e POSTGRES_USER=litellm \
        -e POSTGRES_PASSWORD="$PG_PASSWORD" \
        -e POSTGRES_DB=litellm \
        -p 127.0.0.1:"$PG_PORT":5432 \
        -v ai-gateway-pgdata:/var/lib/postgresql/data \
        --restart unless-stopped \
        postgres:16-alpine >/dev/null
    fi
    printf 'waiting for postgres'
    for i in $(seq 1 45); do
      if docker exec "$PG_CONTAINER" pg_isready -U litellm -d litellm >/dev/null 2>&1; then
        echo " → ready on 127.0.0.1:$PG_PORT"; exit 0
      fi
      printf '.'; sleep 1
    done
    echo; echo "postgres did not become ready; see: docker logs $PG_CONTAINER" >&2; exit 1 ;;
  down)  docker stop "$PG_CONTAINER" >/dev/null && echo "postgres stopped" ;;
  destroy)
    docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
    docker volume rm ai-gateway-pgdata >/dev/null 2>&1 || true
    echo "postgres container + data volume removed" ;;
  *) echo "usage: $0 {up|down|destroy}" >&2; exit 2 ;;
esac
