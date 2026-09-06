#!/usr/bin/env bash
# Back up the gateway's Postgres: virtual keys, budgets and the spend ledger.
#
# Worth doing because virtual-key secrets are shown exactly once, at creation.
# Lose this database and every issued key becomes unusable — as happened once
# already when keys.env was truncated.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
DIR="${BACKUP_DIR:-$HOME/.local/share/ai-gateway-backups}"
mkdir -p "$DIR"; chmod 700 "$DIR"
F="$DIR/litellm-$(date +%Y%m%d-%H%M%S).sql.gz"

docker exec "$PG_CONTAINER" pg_dump -U litellm -d litellm | gzip > "$F"
chmod 600 "$F"
echo "wrote $F ($(du -h "$F" | cut -f1))"

# Keep the 14 most recent, drop the rest.
ls -1t "$DIR"/litellm-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm --
echo "retained $(ls -1 "$DIR"/litellm-*.sql.gz 2>/dev/null | wc -l) backups in $DIR"
