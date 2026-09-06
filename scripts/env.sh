# Point your tools at the gateway:   source scripts/env.sh
# Uses the dev-workstation virtual key.
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; source "$_d/.env"; source "$_d/keys.env"; set +a

# Generic / OpenAI-compatible tools (aider, continue.dev, LangChain, LlamaIndex,
# OpenAI SDK, most self-hosted UIs)
export OPENAI_BASE_URL="http://$GATEWAY_HOST:$GATEWAY_PORT/v1"
export OPENAI_API_KEY="$DEV_WORKSTATION_KEY"

# Anthropic-SDK tools (and Claude Code, if you want it billed through here)
export ANTHROPIC_BASE_URL="http://$GATEWAY_HOST:$GATEWAY_PORT"
export ANTHROPIC_AUTH_TOKEN="$DEV_WORKSTATION_KEY"

# For the example clients in clients/
export AI_GATEWAY_URL="http://$GATEWAY_HOST:$GATEWAY_PORT/v1"
export AI_GATEWAY_BASE="http://$GATEWAY_HOST:$GATEWAY_PORT"
export AI_GATEWAY_KEY="$DEV_WORKSTATION_KEY"

echo "→ tools now point at http://$GATEWAY_HOST:$GATEWAY_PORT (key: dev-workstation)"
echo "  tiers: routine  routine-code  embed  bulk-cloud  balanced  frontier"
unset _d
