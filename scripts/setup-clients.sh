#!/usr/bin/env bash
# Point the local agent CLIs at the gateway. Re-runnable.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; source keys.env; set +a
BASE="http://$GATEWAY_HOST:$GATEWAY_PORT"

echo "configuring clients against $BASE"

# Cline — writes ~/.cline/data/settings/providers.json, which the VS Code
# extension reads too (same schema: lastUsedProvider + openai-compatible).
if command -v cline >/dev/null; then
  cline auth -p openai -k "$DEV_WORKSTATION_KEY" -b "$BASE/v1" -m balanced >/dev/null
  echo "  ✓ cline        → openai-compatible / balanced"
else
  echo "  - cline not installed"
fi

# aider has no persistent provider config we should own; give it a wrapper.
cat > "$PWD/scripts/gw-aider" <<'EOF'
#!/usr/bin/env bash
# aider through the gateway:  scripts/gw-aider [--model openai/frontier] ...
set -euo pipefail
d="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$d/.env"; source "$d/keys.env"; set +a
export OPENAI_API_BASE="http://$GATEWAY_HOST:$GATEWAY_PORT/v1"
export OPENAI_API_KEY="$DEV_WORKSTATION_KEY"
exec aider --model "${AIDER_MODEL:-openai/balanced}" "$@"
EOF
chmod +x "$PWD/scripts/gw-aider"
echo "  ✓ aider        → scripts/gw-aider (AIDER_MODEL=openai/<tier> to switch)"

echo
echo "VS Code: Cline is installed. Open it once and confirm the provider shows"
echo "  'OpenAI Compatible → balanced'. If it asks for credentials, the base URL"
echo "  is $BASE/v1 and the key is DEV_WORKSTATION_KEY from keys.env"
echo "  (VS Code keeps secrets in its own SecretStorage, which nothing outside"
echo "   VS Code can write to)."
