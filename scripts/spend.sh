#!/usr/bin/env bash
# Where the money went. Reads the gateway's ledger directly.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
q() { docker exec "$PG_CONTAINER" psql -U litellm -d litellm -c "$1"; }

echo "── spend by model ─────────────────────────────────────────────"
q "select model,
          count(*)                              as calls,
          sum(prompt_tokens)                    as tok_in,
          sum(completion_tokens)                as tok_out,
          '\$' || to_char(sum(spend)::numeric, 'FM990.000000') as cost
   from \"LiteLLM_SpendLogs\"
   group by model order by sum(spend) desc;"

echo "── spend by key (who is spending it) ──────────────────────────"
q "select coalesce(k.key_alias, 'master/unattributed') as key_alias,
          count(*)                              as calls,
          '\$' || to_char(sum(s.spend)::numeric, 'FM990.000000') as cost
   from \"LiteLLM_SpendLogs\" s
   left join \"LiteLLM_VerificationToken\" k on k.token = s.api_key
   group by 1 order by sum(s.spend) desc;"

echo "── budgets remaining ──────────────────────────────────────────"
q "select key_alias,
          '\$' || to_char(spend::numeric, 'FM990.000000')     as spent,
          '\$' || to_char(max_budget::numeric, 'FM990.00')    as budget,
          budget_duration as period
   from \"LiteLLM_VerificationToken\"
   where key_alias is not null order by key_alias;"

echo "── local vs cloud split (the whole point) ─────────────────────"
q "select case when model in ('qwen2.5:3b-instruct','qwen2.5-coder:14b','nomic-embed-text')
                 or model like 'ollama%' then 'local (free)' else 'cloud (paid)' end as tier,
          count(*) as calls,
          '\$' || to_char(sum(spend)::numeric, 'FM990.000000') as cost
   from \"LiteLLM_SpendLogs\" group by 1 order by 1;"
