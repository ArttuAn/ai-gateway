#!/usr/bin/env bash
# Render LiteLLM's JSON logs as readable lines. Non-JSON lines pass through.
# json_logs stays on in config (structured logs are the right thing to store);
# this is purely the human view.
set -uo pipefail
cd "$(dirname "$0")/.."
tail -n 300 -F logs/gateway.log 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    \{*) out=$(jq -rj '
            (.timestamp // "")[11:19] as $t
          | (.level // "INFO") as $l
          | (.message // "" | gsub("\n";" ") | gsub("\\s+";" ")) as $m
          | "\($t) \($l) \($m)"' <<<"$line" 2>/dev/null) || out="$line" ;;
    *)   out="$line" ;;
  esac
  # Hide known-benign noise so a real problem is visible when it appears.
  # GW_LOG_VERBOSE=1 shows everything. `gw errors` explains each pattern.
  if [ "${GW_LOG_VERBOSE:-0}" != "1" ]; then
    case "$out" in
      *liveliness*|*/metrics*|*opentelemetry*|*weave*|*"Could not import"*) continue ;;
      *_Prisma__engine*|*prisma-query-engine*|*"Prisma DB reconnect"*|*"Backing off connect"*) continue ;;
      *register_model*"custom pricing"*) continue ;;
      *"key not allowed to access model"*|*"Budget has been exceeded"*) continue ;;
    esac
  fi
  case "$out" in
    *ERROR*) printf '\033[31m%s\033[0m\n' "${out:0:400}" ;;
    *WARNING*) printf '\033[33m%s\033[0m\n' "${out:0:400}" ;;
    *) printf '\033[2m%s\033[0m\n' "${out:0:400}" ;;
  esac
done
