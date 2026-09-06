#!/usr/bin/env bash
# Budget + health watchdog. Runs on a timer and notifies only when something
# needs you — the point of an alert is to be rare.
#
# Checks: daily spend threshold, month-to-date vs the sum of key budgets,
# any key past 80% of its budget, gateway/db/redis/ollama liveness, and the
# cloud error rate over the last hour.
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env 2>/dev/null || true; set +a
ICON="$PWD/assets/ai-gateway.svg"
STATE="${XDG_RUNTIME_DIR:-/tmp}/ai-gateway-watch"
mkdir -p "$STATE"

DAILY_LIMIT="${ALERT_DAILY_USD:-5.00}"
KEY_PCT="${ALERT_KEY_PCT:-80}"
ERR_PCT="${ALERT_ERROR_PCT:-25}"

notify() { # urgency title body  — deduped for 6h so a standing problem nags once
  local key; key="$STATE/$(echo "$2" | tr -cd 'a-zA-Z0-9')"
  if [ -f "$key" ] && [ $(( $(date +%s) - $(stat -c %Y "$key") )) -lt 21600 ]; then return; fi
  touch "$key"
  notify-send -a "AI Gateway" -u "$1" -i "$ICON" "$2" "$3" 2>/dev/null || true
  echo "[$(date -Iseconds)] $2 — $3" >> logs/alerts.log
  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -sf -m 10 -X POST "$SLACK_WEBHOOK_URL" -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg t "$2" --arg b "$3" '{text:("*"+$t+"*\n"+$b)}')" >/dev/null || true
  fi
}
q() { docker exec "${PG_CONTAINER:-ai-gateway-db}" psql -U litellm -d litellm -t -A -c "$1" 2>/dev/null; }

# ── liveness ───────────────────────────────────────────────────────────────
curl -sf -m 5 "http://${GATEWAY_HOST:-127.0.0.1}:${GATEWAY_PORT:-4000}/health/liveliness" >/dev/null 2>&1 \
  || notify critical "Gateway is down" "Nothing can reach the gateway. Try: gw doctor"
docker exec "${PG_CONTAINER:-ai-gateway-db}" pg_isready -U litellm -d litellm >/dev/null 2>&1 \
  || notify critical "Database is down" "Spend tracking and virtual keys are unavailable."
docker exec "${REDIS_CONTAINER:-ai-gateway-redis}" redis-cli -a "${REDIS_PASSWORD:-}" --no-auth-warning ping 2>/dev/null | grep -q PONG \
  || notify normal "Redis is down" "Rate limits fall back to per-worker counters and stop being exact."
curl -sf -m 5 "${OLLAMA_API_BASE:-http://127.0.0.1:11434}/api/tags" >/dev/null 2>&1 \
  || notify normal "Local models unavailable" "Routine work is failing over to paid cloud models."

# ── spend ──────────────────────────────────────────────────────────────────
DAY=$(q "select coalesce(round(sum(spend)::numeric,4),0) from \"LiteLLM_SpendLogs\" where \"startTime\" > now() - interval '24 hours';")
if [ -n "$DAY" ] && awk "BEGIN{exit !($DAY > $DAILY_LIMIT)}"; then
  notify critical "Spend above daily threshold" "\$$DAY in 24h (limit \$$DAILY_LIMIT). Check: gw spend"
fi

while IFS='|' read -r alias spent budget pct; do
  [ -z "${alias:-}" ] && continue
  notify normal "Key near its budget" "$alias: \$$spent of \$$budget (${pct}%)"
done < <(q "select key_alias, round(spend::numeric,4), round(max_budget::numeric,2),
                   round((spend/nullif(max_budget,0)*100)::numeric,0)
            from \"LiteLLM_VerificationToken\"
            where key_alias is not null and max_budget > 0
              and spend/nullif(max_budget,0)*100 >= $KEY_PCT;")

# ── error rate (cloud only; local failing over is already alerted above) ────
read -r TOT ERR < <(q "select count(*), count(*) filter (where \"user\" = 'litellm-internal-error' or spend = 0 and completion_tokens = 0)
                       from \"LiteLLM_SpendLogs\" where \"startTime\" > now() - interval '1 hour';" | tr '|' ' ')
if [ "${TOT:-0}" -ge 20 ] 2>/dev/null; then
  RATE=$(( ${ERR:-0} * 100 / TOT ))
  [ "$RATE" -ge "$ERR_PCT" ] && notify normal "Elevated failure rate" "${RATE}% of the last $TOT requests produced no output."
fi

echo "watch ok $(date -Iseconds) — 24h spend \$$DAY"
