#!/usr/bin/env bash
# Full bootstrap from a clean checkout. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/5] python env + litellm"
[ -d .venv ] || uv venv --python 3.12 .venv
VIRTUAL_ENV="$PWD/.venv" uv pip install -q 'litellm[proxy]' prisma

echo "[2/5] prisma client"
set -a; source .env; set +a
export PATH="$PWD/.venv/bin:$PATH"
SCHEMA=".venv/lib/python3.12/site-packages/litellm/proxy/schema.prisma"
.venv/bin/prisma generate --schema="$SCHEMA" >/dev/null

echo "[3/5] postgres"
./scripts/db.sh up

echo "[4/5] database schema"
.venv/bin/prisma db push --schema="$SCHEMA" --accept-data-loss --skip-generate >/dev/null
echo "      schema in sync"

echo "[5/5] local models"
for m in qwen2.5:3b-instruct nomic-embed-text; do
  ollama list 2>/dev/null | grep -q "^${m%%:*}" || ollama pull "$m"
done

echo
echo "done. next:  ./scripts/start.sh  &&  ./scripts/provision-keys.sh"
