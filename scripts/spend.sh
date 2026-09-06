#!/usr/bin/env bash
# Where the money went. Reads the gateway's ledger directly.
#
# How a row's cost is produced: the provider returns real token counts, LiteLLM
# multiplies them by the per-token prices declared in config/config.yaml, and
# writes the result to LiteLLM_SpendLogs.spend. This script only sums that
# column — it never estimates.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
q() { docker exec "$PG_CONTAINER" psql -U litellm -d litellm -c "$1"; }

# Model names arrive two ways: with a provider prefix when reached through a
# tier ("anthropic/claude-sonnet-5"), and bare when reached by its passthrough
# name ("claude-sonnet-5"). Same model, same bill — so normalise before
# grouping, or one model reports as two rows.
NORM="split_part(model,'/',-1)"
# Failed requests (auth denials, budget blocks) are logged with 0 tokens and
# $0. They are not spend; counting them as model rows is misleading.
OK="coalesce(metadata->>'status','ok') <> 'failure'"
# Same predicate, table-qualified: both joined tables have a metadata column.
OK_S="coalesce(s.metadata->>'status','ok') <> 'failure'"

echo "── spend by model ─────────────────────────────────────────────"
q "select $NORM as model,
          count(*) as calls,
          sum(prompt_tokens) as tok_in,
          sum(completion_tokens) as tok_out,
          '\$' || to_char(sum(spend)::numeric, 'FM990.000000') as cost
   from \"LiteLLM_SpendLogs\" where $OK
   group by 1 order by sum(spend) desc;"

echo "── spend by key (who is spending it) ──────────────────────────"
q "select coalesce(k.key_alias, 'master/unattributed') as key_alias,
          count(*) as calls,
          '\$' || to_char(sum(s.spend)::numeric, 'FM990.000000') as cost
   from \"LiteLLM_SpendLogs\" s
   left join \"LiteLLM_VerificationToken\" k on k.token = s.api_key
   where $OK_S
   group by 1 order by sum(s.spend) desc;"

echo "── budgets remaining ──────────────────────────────────────────"
echo "   (LiteLLM's own counter; lags the log by up to proxy_batch_write_at=60s)"
q "select key_alias,
          '\$' || to_char(spend::numeric, 'FM990.000000') as spent,
          '\$' || to_char(max_budget::numeric, 'FM990.00') as budget,
          case when max_budget > 0
               then to_char((spend/max_budget*100)::numeric,'FM9999990') || '%'
               else '-' end as used,
          budget_duration as period
   from \"LiteLLM_VerificationToken\"
   where key_alias is not null order by key_alias;"

echo "── local vs cloud split (the whole point) ─────────────────────"
q "select case when model like 'ollama%' or $NORM in
                    ('qwen2.5:3b-instruct','qwen2.5-coder:14b','nomic-embed-text')
              then 'local (free)' else 'cloud (paid)' end as tier,
          count(*) as calls,
          sum(prompt_tokens+completion_tokens) as tokens,
          '\$' || to_char(sum(spend)::numeric, 'FM990.000000') as cost
   from \"LiteLLM_SpendLogs\" where $OK group by 1 order by 1;"

echo "── refused requests (guardrails firing; no cost) ──────────────"
q "select $NORM as attempted_model, count(*) as blocked
   from \"LiteLLM_SpendLogs\"
   where coalesce(metadata->>'status','ok') = 'failure'
   group by 1 order by 2 desc;"
