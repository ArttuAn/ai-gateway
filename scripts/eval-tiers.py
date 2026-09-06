#!/usr/bin/env python3
"""
Measure each tier against a golden task set, so routing is an evidence-based
decision rather than a guess.

The industry practice this implements: don't decide "local is good enough for
X" by feel — run representative tasks through every tier and compare pass
rate, latency and cost. Re-run it when you change models or prompts.

    scripts/eval-tiers.py                          # default tiers
    scripts/eval-tiers.py --tiers routine,balanced
    scripts/eval-tiers.py --repeat 3               # average over runs
"""
import argparse, json, os, re, statistics, sys, time, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read_env(name):
    out = {}
    p = ROOT / name
    if not p.exists():
        return out
    for line in p.read_text().splitlines():
        m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip("\"'")
    return out


CFG = {**read_env(".env"), **read_env("keys.env")}
BASE = f"http://{CFG.get('GATEWAY_HOST','127.0.0.1')}:{CFG.get('GATEWAY_PORT','4000')}"
KEY = CFG.get("DEV_WORKSTATION_KEY")


def call(model, prompt, timeout):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 400, "temperature": 0,
    }).encode()
    req = urllib.request.Request(
        f"{BASE}/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read())
    return d["choices"][0]["message"]["content"] or "", time.time() - t0, d.get("model", model), d.get("usage", {})


# ── checks ─────────────────────────────────────────────────────────────────
def strip_fences(t):
    return re.sub(r"^\s*```[a-zA-Z]*\s*|\s*```\s*$", "", t.strip())


def check(spec, text):
    t = text.strip()
    k = spec["type"]
    if k == "contains_ci":
        return spec["value"].lower() in t.lower()
    if k == "all_contains_ci":
        return all(v.lower() in t.lower() for v in spec["values"])
    if k == "regex":
        return re.search(spec["value"], t.strip(), re.M) is not None
    if k == "max_words":
        return len(t.split()) <= spec["value"]
    if k == "json_has":
        try:
            o = json.loads(strip_fences(t))
        except Exception:
            return False
        return isinstance(o, dict) and all(x in o for x in spec["keys"])
    if k == "regex_matches_samples":
        pat = strip_fences(t).strip().strip("/")
        try:
            rx = re.compile(pat)
        except re.error:
            return False
        return (all(rx.search(s) for s in spec["positive"])
                and not any(rx.fullmatch(s) for s in spec["negative"]))
    raise ValueError(f"unknown check {k}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiers", default="routine,routine-code,bulk-cloud,balanced")
    ap.add_argument("--tasks", default=str(ROOT / "evals" / "tasks.jsonl"))
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()

    if not KEY:
        sys.exit("DEV_WORKSTATION_KEY missing from keys.env — run: make keys")

    tasks = [json.loads(l) for l in Path(a.tasks).read_text().splitlines() if l.strip()]
    tiers = [t.strip() for t in a.tiers.split(",") if t.strip()]
    results = {}

    for tier in tiers:
        rows, lat, cost_tokens = [], [], 0
        print(f"\n▶ {tier}", flush=True)
        for task in tasks:
            passes, times = 0, []
            for _ in range(a.repeat):
                try:
                    out, dt, served, usage = call(tier, task["prompt"], a.timeout)
                    ok = check(task["check"], out)
                    cost_tokens += usage.get("total_tokens", 0) or 0
                except Exception as e:
                    ok, dt, out = False, 0.0, f"ERROR: {type(e).__name__}: {e}"
                passes += 1 if ok else 0
                times.append(dt)
            rate = passes / a.repeat
            rows.append((task["id"], task["kind"], rate))
            lat.extend(times)
            mark = "✓" if rate == 1 else ("~" if rate > 0 else "✗")
            print(f"   {mark} {task['id']:<20} {rate*100:5.0f}%  {statistics.mean(times):6.1f}s", flush=True)
        results[tier] = {
            "rows": rows,
            "pass": sum(r for _, _, r in rows) / len(rows),
            "p50": statistics.median(lat),
            "tokens": cost_tokens,
        }

    # ── summary ────────────────────────────────────────────────────────────
    print("\n" + "═" * 74)
    print(f"{'tier':<16}{'pass rate':>11}{'median latency':>17}{'tokens':>10}")
    print("─" * 74)
    for tier, r in results.items():
        print(f"{tier:<16}{r['pass']*100:>10.0f}%{r['p50']:>16.1f}s{r['tokens']:>10}")

    print("\nper-task (rows where a cheap tier already passes are safe to route down)")
    ids = [t["id"] for t in tasks]
    print(f"{'task':<20}" + "".join(f"{t[:12]:>14}" for t in tiers))
    for i, tid in enumerate(ids):
        line = f"{tid:<20}"
        for tier in tiers:
            rate = results[tier]["rows"][i][2]
            line += f"{('✓' if rate == 1 else '~' if rate > 0 else '✗'):>14}"
        print(line)

    cheap = tiers[0]
    safe = [t["id"] for i, t in enumerate(tasks) if results[cheap]["rows"][i][2] == 1]
    print(f"\n{cheap} handles {len(safe)}/{len(tasks)}: {', '.join(safe) if safe else '(none)'}")
    print("Route those locally; send the rest to a cloud tier.")


if __name__ == "__main__":
    main()
