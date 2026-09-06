#!/usr/bin/env bash
# Operational snapshot from the gateway's Prometheus endpoint.
# Point a real Prometheus at http://127.0.0.1:4000/metrics for history.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
M=$(curl -sfL "http://$GATEWAY_HOST:$GATEWAY_PORT/metrics" -H "Authorization: Bearer $LITELLM_MASTER_KEY") \
  || { echo "no /metrics — is the prometheus callback enabled and the gateway up?" >&2; exit 1; }

show() { # metric-prefix  label
  local out
  out=$(grep -E "^$1" <<<"$M" | grep -v '^#' | head -12)
  [ -n "$out" ] && { echo "── $2"; sed 's/^/  /' <<<"$out"; echo; }
}
show 'litellm_spend_metric_total'          'spend by model/key'
show 'litellm_total_tokens_metric_total'   'tokens'
show 'litellm_proxy_total_requests_metric' 'requests by status'
show 'litellm_proxy_failed_requests_metric' 'failures'
show 'litellm_request_total_latency'       'latency'
show 'litellm_deployment_state'            'deployment health (0=healthy)'
echo "raw: curl -s http://$GATEWAY_HOST:$GATEWAY_PORT/metrics -H 'Authorization: Bearer \$LITELLM_MASTER_KEY'"
