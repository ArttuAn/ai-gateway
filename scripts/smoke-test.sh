#!/usr/bin/env bash
# End-to-end check of every tier and guardrail.
# Costs a few tenths of a cent in cloud calls.
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; source keys.env; set +a
GW="http://$GATEWAY_HOST:$GATEWAY_PORT"
K="$DEV_WORKSTATION_KEY"
pass=0; fail=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no()  { printf '  \033[31m✗\033[0m %s — %s\n' "$1" "${2:0:160}"; fail=$((fail+1)); }

chat() { # model prompt extra_json
  curl -s -m 300 "$GW/v1/chat/completions" -H "Authorization: Bearer ${4:-$K}" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg m "$1" --arg p "$2" --argjson x "${3:-{\}}" \
          '{model:$m, messages:[{role:"user",content:$p}], max_tokens:2000} + $x')"
}

echo "gateway smoke test → $GW"

r=$(curl -s -m 10 "$GW/v1/models" -H "Authorization: Bearer $K" | jq -r '.data|length')
[ "$r" -ge 6 ] 2>/dev/null && ok "model list ($r models)" || no "model list" "$r"

for tier in routine bulk-cloud balanced; do
  c=$(chat "$tier" "Reply with exactly: ok" | jq -r '.choices[0].message.content // empty')
  [ -n "$c" ] && ok "$tier → '$c'" || no "$tier" "no content"
done

c=$(chat frontier "Reply with exactly: ok" '{"thinking":{"type":"adaptive"},"output_config":{"effort":"low"},"max_tokens":16000}' | jq -r '.choices[0].message.content // empty')
[ -n "$c" ] && ok "frontier + adaptive thinking → '$c'" || no "frontier + thinking" "no content"

d=$(curl -s -m 60 "$GW/v1/embeddings" -H "Authorization: Bearer $K" -H 'Content-Type: application/json' \
     -d '{"model":"embed","input":"test"}' | jq -r '.data[0].embedding|length')
[ "$d" = "768" ] && ok "embeddings (local, $d dims)" || no "embeddings" "$d"

a=$(curl -s -m 120 "$GW/v1/messages" -H "x-api-key: $K" -H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json' \
     -d '{"model":"bulk-cloud","max_tokens":20,"messages":[{"role":"user","content":"Reply with exactly: ok"}]}' | jq -r '.content[0].text // empty')
[ -n "$a" ] && ok "Anthropic /v1/messages → '$a'" || no "Anthropic /v1/messages" "no content"

s=$(chat frontier hi '{}' "$SANDBOX_LOCAL_KEY" | jq -r '.error.message // "ALLOWED"')
[[ "$s" == *"not allowed"* ]] && ok "sandbox key blocked from frontier" || no "allowlist enforcement" "$s"

st=$(curl -s -m 120 -N "$GW/v1/chat/completions" -H "Authorization: Bearer $K" -H 'Content-Type: application/json' \
      -d '{"model":"bulk-cloud","messages":[{"role":"user","content":"hi"}],"max_tokens":10,"stream":true}' | grep -c '^data:')
[ "$st" -ge 1 ] && ok "streaming ($st chunks)" || no "streaming" "$st"

echo; echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
