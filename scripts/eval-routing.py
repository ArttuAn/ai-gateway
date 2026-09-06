#!/usr/bin/env python3
"""
Measure whether `auto` routes CORRECTLY — not whether the tiers are good.

`eval-tiers.py` answers "how well does each tier do the work". This answers the
different and previously unmeasured question: "does the router send each
request to the right tier". Without this, routing thresholds are somebody's
opinion.

Each task is labelled local|cloud. We send it to `auto` with max_tokens=1
(we care about the routing decision, not the answer — this keeps the eval
cheap) and read the actual backend from the x-litellm-model-name header.

    scripts/eval-routing.py
    scripts/eval-routing.py --verbose      # show every decision
"""
import argparse, json, re, sys, time, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read_env(name):
    out, p = {}, ROOT / name
    if p.exists():
        for line in p.read_text().splitlines():
            m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
            if m:
                out[m.group(1)] = m.group(2).strip().strip("\"'")
    return out


CFG = {**read_env(".env"), **read_env("keys.env")}
BASE = f"http://{CFG.get('GATEWAY_HOST','127.0.0.1')}:{CFG.get('GATEWAY_PORT','4000')}"
KEY = CFG.get("DEV_WORKSTATION_KEY")
LOCAL_MARKERS = ("ollama", "qwen")


def route_of(prompt, timeout=300):
    """Return the backend that `auto` picked, without paying for a full answer."""
    body = json.dumps({
        "model": "auto",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 1, "temperature": 0,
    }).encode()
    req = urllib.request.Request(
        f"{BASE}/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.headers.get("x-litellm-model-name", "?")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", default=str(ROOT / "evals" / "routing.jsonl"))
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    if not KEY:
        sys.exit("DEV_WORKSTATION_KEY missing — run: gw keys")

    tasks = [json.loads(l) for l in Path(a.tasks).read_text().splitlines() if l.strip()]
    rows, correct = [], 0

    print(f"routing accuracy — {len(tasks)} labelled prompts\n")
    for t in tasks:
        try:
            backend = route_of(t["prompt"])
            got = "local" if any(m in backend.lower() for m in LOCAL_MARKERS) else "cloud"
        except Exception as e:
            backend, got = f"ERROR: {type(e).__name__}", "error"
        ok = got == t["expect"]
        correct += ok
        rows.append({"id": t["id"], "expect": t["expect"], "got": got,
                     "backend": backend, "ok": ok, "why": t.get("why", "")})
        mark = "✓" if ok else "✗"
        line = f"  {mark} {t['id']:<18} want {t['expect']:<6} got {got:<6}"
        if a.verbose or not ok:
            line += f"  {backend.split('/')[-1]}"
        print(line, flush=True)

    acc = correct / len(tasks)
    # Costly mistakes are asymmetric: sending cloud work to a weak local model
    # produces a wrong answer; sending trivial work to cloud only wastes money.
    under = [r for r in rows if r["expect"] == "cloud" and r["got"] == "local"]
    over = [r for r in rows if r["expect"] == "local" and r["got"] == "cloud"]

    print(f"\n{'═'*62}")
    print(f"accuracy: {correct}/{len(tasks)}  ({acc*100:.0f}%)")
    print(f"  under-routed (cloud work sent local — WRONG ANSWERS): {len(under)}")
    for r in under:
        print(f"      {r['id']}: {r['why']}")
    print(f"  over-routed  (trivial work sent to cloud — WASTED SPEND): {len(over)}")
    for r in over:
        print(f"      {r['id']}")
    if under:
        print("\n  fix: lower tier_boundaries.simple_medium, lower")
        print("       heuristic_first_max_tier, or add a keyword_tier_rule.")
    elif over:
        print("\n  over-routing only: cheap to leave alone (a fraction of a cent),")
        print("  and safer than the alternative. Raising tier_boundaries.simple_medium")
        print("  pulls MORE prompts into SIMPLE and has been measured to cause")
        print("  under-routing — re-run this eval if you change it.")
    else:
        print("\n  routing matches every label.")

    out = ROOT / "evals" / "routing-results.json"
    out.write_text(json.dumps({
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "accuracy": round(acc, 3),
        "under_routed": [r["id"] for r in under],
        "over_routed": [r["id"] for r in over],
        "rows": rows,
    }, indent=2) + "\n")
    print(f"\nwrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
