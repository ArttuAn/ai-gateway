#!/usr/bin/env bash
# On-demand health of every deployment. NOTE: this bills one tiny request
# per cloud model — run it when debugging, not on a cron.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
curl -s "http://$GATEWAY_HOST:$GATEWAY_PORT/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | jq '{healthy: [.healthy_endpoints[]?.model], unhealthy: [.unhealthy_endpoints[]? | {model, error: (.error // "")[0:120]}], counts: {healthy: .healthy_count, unhealthy: .unhealthy_count}}'
