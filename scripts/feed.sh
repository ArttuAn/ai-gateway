#!/usr/bin/env bash
# Live routing feed: what the gateway decided, per request.
# Spend rows flush every 60s (proxy_batch_write_at), so entries appear in
# batches rather than instantly — that's the production setting, not a bug.
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env 2>/dev/null || true; set +a
SEEN="${XDG_RUNTIME_DIR:-/tmp}/gw-feed-seen"; : > "$SEEN"
printf '\033[1m %-8s %-22s %-10s %-9s %s\033[0m\n' TIME MODEL TIER DECIDED COST
printf '%s\n' " ────────────────────────────────────────────────────────────────────"
printf '\033[2m %s\033[0m\n' "'direct' = called a tier by name (incl. the router's own classifier call)"
while true; do
  docker exec "${PG_CONTAINER:-ai-gateway-db}" psql -U litellm -d litellm -t -A -F'|' -c "
    select request_id, to_char(\"startTime\",'HH24:MI:SS'),
           split_part(model,'/',-1),
           coalesce(metadata->'routing_decision'->>'tier','direct'),
           coalesce(replace(metadata->'routing_decision'->>'cause','heuristic_first_short_circuit','heuristic'),'not-auto'),
           round(spend::numeric,6)
    from \"LiteLLM_SpendLogs\" where \"startTime\" > now() - interval '2 hours'
    order by \"startTime\";" 2>/dev/null | while IFS='|' read -r id t model tier cause cost; do
      [ -z "${id:-}" ] && continue
      grep -qxF "$id" "$SEEN" 2>/dev/null && continue
      echo "$id" >> "$SEEN"
      case "$cost" in 0.000000) C=$'\033[32m    free\033[0m';; *) C=$'\033[33m'"$(printf '%8s' "\$$cost")"$'\033[0m';; esac
      printf ' %-8s %-22s %-10s %-9s %b\n' "$t" "${model:0:22}" "$tier" "${cause:0:9}" "$C"
    done
  sleep 4
done
