"""
Talking to the gateway with the official Anthropic SDK.

The gateway also speaks Anthropic's native /v1/messages, so existing Anthropic
code keeps working — you change base_url and api_key, nothing else. You then
get budgets, spend attribution and fallbacks for free, and you can point the
same code at a LOCAL model just by changing the model string.

    pip install anthropic
    python clients/python_anthropic.py
"""
import os
from anthropic import Anthropic

client = Anthropic(
    base_url=os.environ.get("AI_GATEWAY_BASE", "http://127.0.0.1:4000"),
    api_key=os.environ["AI_GATEWAY_KEY"],
)

# Hard task → frontier, with adaptive thinking (the current API; there is no
# budget_tokens on Opus 5 — it is rejected).
resp = client.messages.create(
    model="frontier",
    max_tokens=16000,
    thinking={"type": "adaptive"},
    messages=[{"role": "user", "content": "Explain in 2 sentences why an LLM gateway beats calling providers directly."}],
)
print("frontier:", "".join(b.text for b in resp.content if b.type == "text"))
print("usage:", resp.usage.input_tokens, "in /", resp.usage.output_tokens, "out")

# Same SDK, same code path, zero cost — just a different tier name.
local = client.messages.create(
    model="routine",
    max_tokens=50,
    messages=[{"role": "user", "content": "Reply with one word: local"}],
)
print("routine:", "".join(b.text for b in local.content if b.type == "text"))
