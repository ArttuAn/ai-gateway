#!/usr/bin/env bash
# Provision teams + virtual keys. Idempotent: existing aliases are left alone.
#
# Why virtual keys: your real ANTHROPIC_API_KEY never leaves this box. Every
# app, script and teammate gets a scoped key with its own budget and model
# allowlist, revocable individually, with per-key spend attribution.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
GW="http://$GATEWAY_HOST:$GATEWAY_PORT"
AUTH="Authorization: Bearer $LITELLM_MASTER_KEY"
OUT="keys.env"

api() { curl -s -X "$1" "$GW$2" -H "$AUTH" -H 'Content-Type: application/json' -d "$3"; }

list_aliases() {
  curl -s "$GW/key/list?return_full_object=true&size=100" -H "$AUTH" \
    | jq -r '[.keys[]? | (if type=="object" then .key_alias else . end)] | map(select(.!=null)) | .[]' 2>/dev/null
}
existing="$(list_aliases || true)"
if [ -z "$existing" ]; then
  echo "note: could not read existing key aliases — duplicates will be reported, not created." >&2
fi

mk_key() { # alias  models_json  budget  duration  rpm  description
  local alias="$1" models="$2" budget="$3" dur="$4" rpm="$5" desc="$6"
  if grep -qx "$alias" <<<"$existing"; then
    echo "  = $alias (already exists, skipped)"; return
  fi
  local body key
  body=$(jq -nc --arg a "$alias" --argjson m "$models" --argjson b "$budget" \
           --arg d "$dur" --argjson r "$rpm" --arg desc "$desc" \
           '{key_alias:$a, models:$m, max_budget:$b, budget_duration:$d, rpm_limit:$r, metadata:{purpose:$desc}}')
  local resp; resp=$(api POST /key/generate "$body")
  key=$(jq -r '.key // empty' <<<"$resp")
  if [ -n "$key" ]; then
    printf '%s=%s\n' "$(tr 'a-z-' 'A-Z_' <<<"$alias")_KEY" "$key" >> "$OUT"
    echo "  + $alias  → budget \$$budget/$dur, models: $(jq -r 'join(", ")' <<<"$models")"
  else
    echo "  ! $alias FAILED: $(jq -rc '.error.message // .detail // .' <<<"$resp" | head -c 160)" >&2
  fi
}

# Never clobber keys.env: a virtual key's secret is shown once, at creation.
# Rewriting the file would strand every key that already exists.
if [ ! -f "$OUT" ]; then
  echo "# Virtual keys for the AI gateway — generated $(date -Iseconds)" > "$OUT"
  echo "# Give each app ONE of these, never the master key or the Anthropic key." >> "$OUT"
fi
chmod 600 "$OUT"

echo "provisioning keys:"

# Your own workstation: everything, incl. frontier. Generous ceiling as a
# runaway-loop tripwire rather than a real limit.
mk_key dev-workstation \
  '["routine","routine-code","embed","bulk-cloud","balanced","frontier","claude-opus-5","claude-sonnet-5","claude-haiku-4-5"]' \
  100 30d 240 "interactive dev: IDE, Claude Code, ad-hoc CLI"

# Production app path: no frontier. Prod traffic should be predictable;
# if something genuinely needs Opus, that's a deliberate config change here.
mk_key app-backend \
  '["routine","embed","bulk-cloud","balanced"]' \
  50 30d 120 "user-facing product traffic"

# Nightly/batch work: local-first, cheap cloud as the escape hatch.
mk_key batch-jobs \
  '["routine","routine-code","embed","bulk-cloud"]' \
  10 30d 60 "cron, enrichment, backfills, CI"

# Graphical chat UI (Open WebUI). Local tier for everyday questions, with
# haiku/sonnet available when a local 3B answer isn't good enough. No frontier:
# a chat box is exactly where an idle $25/Mtok model quietly drains a budget.
mk_key chat-ui \
  '["routine","routine-code","embed","bulk-cloud","balanced"]' \
  20 30d 120 "Open WebUI graphical chat front-end"

# Experiments / onboarding a new teammate: local only, cannot spend a cent.
mk_key sandbox-local \
  '["sealed-local","sealed-code","embed"]' \
  0.01 30d 60 "sealed local sandbox; no fallback can escalate it to a paid model"

echo
echo "wrote $OUT (chmod 600)"
