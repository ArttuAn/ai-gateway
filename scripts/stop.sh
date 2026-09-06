#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f run/gateway.pid ]; then
  kill "$(cat run/gateway.pid)" 2>/dev/null || true
  sleep 1; rm -f run/gateway.pid; echo "gateway stopped"
else
  pkill -f 'litellm --config config/config.yaml' 2>/dev/null && echo "gateway stopped" || echo "gateway not running"
fi
