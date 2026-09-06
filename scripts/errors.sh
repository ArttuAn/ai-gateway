#!/usr/bin/env bash
# Recent gateway errors, deduped and classified — printed to stdout so you can
# select and copy them normally, instead of fighting tmux's mouse mode.
#
#   gw errors            last 2h, classified
#   gw errors --raw      full text, unclassified (for pasting into an issue)
set -uo pipefail
cd "$(dirname "$0")/.."
RAW=0
[ "${1:-}" = "--raw" ] && RAW=1

extract() {
  tail -n 20000 logs/gateway.log | while IFS= read -r l; do
    case "$l" in
      \{*) jq -r --argjson raw "$RAW" '
             select(.level=="ERROR" or .level=="WARNING")
             | .message as $m
             | "\(.level)|||\($m | gsub("\n";" ") | gsub("\\s+";" ") | if $raw==1 then . else .[0:150] end)"' <<<"$l" 2>/dev/null ;;
    esac
  done
}

explain() {
  case "$1" in
    *_Prisma__engine*|*prisma-query-engine*|*"Prisma DB reconnect"*)
      echo "restart noise - the query engine dies with the proxy and reconnects on backoff" ;;
    *"Could not import litellm.integrations"*)
      echo "optional integration not installed (weave/otel); nothing here uses it" ;;
    *register_model*"custom pricing"*)
      echo "expected - local models are declared at \$0, which is not in LiteLLM's cost map" ;;
    *"key not allowed to access model"*)
      echo "a guardrail firing correctly - a key was refused a model outside its allowlist" ;;
    *"Budget has been exceeded"*)
      echo "a guardrail firing correctly - a key hit its spend cap" ;;
    *) echo "" ;;
  esac
}

if [ "$RAW" = 1 ]; then
  echo "# gateway errors (raw) - $(date -Iseconds)"
  extract | sed 's/|||/  /' | sort -u
  exit 0
fi

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
extract | sort | uniq -c | sort -rn > "$tmp"
benign=0; real=0

printf '\033[1mgateway errors\033[0m\n\n'
while IFS= read -r line; do
  [ -z "$line" ] && continue
  count=$(awk '{print $1}' <<<"$line")
  rest=${line#*"$count"}; rest=${rest# }
  level=${rest%%|||*}
  msg=${rest#*|||}
  why=$(explain "$msg")
  if [ -n "$why" ]; then
    benign=$((benign+1))
    printf '  \033[2m%4sx %-7s %s\033[0m\n       \033[2m^ %s\033[0m\n' "$count" "$level" "${msg:0:104}" "$why"
  else
    real=$((real+1))
    printf '  \033[31m%4sx %-7s %s\033[0m\n       \033[31m^ not a known-benign pattern - worth a look\033[0m\n' "$count" "$level" "${msg:0:104}"
  fi
done < "$tmp"

echo
if [ "$real" -eq 0 ]; then
  printf '  \033[32mall %s pattern(s) are known-benign - nothing needs action\033[0m\n' "$benign"
else
  printf '  \033[31m%s pattern(s) worth investigating\033[0m (%s benign)\n' "$real" "$benign"
fi
echo "  full text to copy/paste:  gw errors --raw"
