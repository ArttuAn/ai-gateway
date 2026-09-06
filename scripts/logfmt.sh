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
  # drop health-check and import noise; keep anything that matters
  case "$out" in
    *liveliness*|*/metrics*|*opentelemetry*|*weave*|*"Could not import"*) continue ;;
  esac
  case "$out" in
    *ERROR*) printf '\033[31m%s\033[0m\n' "${out:0:400}" ;;
    *WARNING*) printf '\033[33m%s\033[0m\n' "${out:0:400}" ;;
    *) printf '\033[2m%s\033[0m\n' "${out:0:400}" ;;
  esac
done
