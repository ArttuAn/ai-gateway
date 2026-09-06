"""
Talking to the gateway with the OpenAI SDK.

The point: this file contains no vendor names and no provider keys. It asks
for a *tier*. Whether that resolves to a 3B model on this laptop or Claude
Opus in the cloud is a gateway config decision, not an application decision.

    pip install openai
    python clients/python_openai.py
"""
import os
from openai import OpenAI

client = OpenAI(
    base_url=os.environ.get("AI_GATEWAY_URL", "http://127.0.0.1:4000/v1"),
    api_key=os.environ["AI_GATEWAY_KEY"],  # a virtual key, never a provider key
)

ROUTINE, BALANCED, FRONTIER = "routine", "balanced", "frontier"


def ask(model: str, prompt: str, **kw) -> str:
    r = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        **kw,
    )
    # The gateway reports which deployment actually served the request —
    # worth logging, because a fallback may have moved it off the local box.
    print(f"  [{model} → served by {r.model}]")
    return r.choices[0].message.content


if __name__ == "__main__":
    # Routine: free, local, good enough. This is where the volume should go.
    print("routine:", ask(ROUTINE, "Sentiment in one word: 'shipping was late but support fixed it fast'", max_tokens=10))

    # Balanced: real reasoning, sane price.
    print("balanced:", ask(BALANCED, "In one sentence, what is a token in an LLM?", max_tokens=100))

    # Frontier: reserve for genuinely hard work. Anthropic-specific params
    # (adaptive thinking, effort) pass straight through the gateway; they are
    # silently dropped for models that don't support them, so the same call
    # shape works against every tier.
    print("frontier:", ask(
        FRONTIER,
        "A cron job silently stopped firing after a DST change. Name the two most likely causes.",
        max_tokens=16000,
        extra_body={"thinking": {"type": "adaptive"}, "output_config": {"effort": "medium"}},
    ))

    # Embeddings run locally and cost nothing.
    e = client.embeddings.create(model="embed", input=["local embeddings are free"])
    print(f"embed: {len(e.data[0].embedding)} dims")
