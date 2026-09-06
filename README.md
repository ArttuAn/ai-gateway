# AI Gateway

One OpenAI-compatible endpoint in front of **local models on this machine** and
**Claude frontier models in the cloud**. Applications ask for a *tier*
(`routine`, `balanced`, `frontier`) instead of naming a vendor, so you can move
work between local and cloud by editing one config file — no application
changes, no redeploys.

Built on [LiteLLM](https://github.com/BerriAI/litellm) + Ollama + Postgres.

```
   your apps / IDE / CLI / cron
              │  one base_url, one virtual key
              ▼
   ┌──────────────────────────┐
   │  gateway  :4000          │  routing · fallbacks · budgets
   │  OpenAI + Anthropic API  │  spend ledger · virtual keys
   └────────┬────────┬────────┘
            │        │
      Ollama :11434  └── Anthropic API
      (free, private)     (frontier, metered)
```

## Tiers

| Tier           | Backend                       | Where      | Cost (in/out per Mtok) | Use for |
|----------------|-------------------------------|------------|------------------------|---------|
| `routine`      | qwen2.5:3b-instruct           | this box   | free                   | classification, extraction, tagging, summaries, commit messages |
| `routine-code` | qwen2.5-coder:14b             | this box   | free                   | local code chores, batch refactors (slow on CPU) |
| `embed`        | nomic-embed-text (768d)       | this box   | free                   | all embeddings / RAG indexing |
| `bulk-cloud`   | claude-haiku-4-5              | Anthropic  | $1 / $5                | high-volume cloud work, local overflow |
| `balanced`     | claude-sonnet-5               | Anthropic  | $2 / $10               | the default for real work |
| `frontier`     | claude-opus-5                 | Anthropic  | $5 / $25               | hard reasoning, long-horizon agents |

Real model ids (`claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5`) are also
exposed for tools that hardcode them — they still land in your spend ledger.

## Quick start

```bash
make setup     # venv, litellm, prisma, postgres, schema, pull local models
make up        # start postgres + gateway
make keys      # mint virtual keys → keys.env
make test      # end-to-end check of every tier
make clients   # point Cline + aider at the gateway
make webui     # graphical chat UI on http://127.0.0.1:3000
```

Or just double-click the **AI Gateway** icon on your desktop — it starts
everything and opens the interfaces. Right-click it for *Stop everything*,
*Show spend report*, and *Open chat UI only*.

Then point anything at it:

```bash
source scripts/env.sh     # sets OPENAI_BASE_URL / ANTHROPIC_BASE_URL + key
python clients/python_openai.py
```

## Using it

**OpenAI SDK / LangChain / aider / continue.dev / most UIs**
```python
client = OpenAI(base_url="http://127.0.0.1:4000/v1", api_key="<virtual key>")
client.chat.completions.create(model="routine", messages=[...])
```

**Anthropic SDK** — the gateway also serves native `/v1/messages`:
```python
client = Anthropic(base_url="http://127.0.0.1:4000", api_key="<virtual key>")
client.messages.create(model="frontier", max_tokens=16000,
                       thinking={"type": "adaptive"}, messages=[...])
```

**curl**
```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $AI_GATEWAY_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"balanced","messages":[{"role":"user","content":"hi"}]}'
```

Anthropic-specific parameters (`thinking`, `output_config.effort`,
`cache_control`) pass straight through to Claude and are dropped automatically
for local models — so one call shape works against every tier.

## The desktop icon

`~/Desktop/AI Gateway` (also in the applications menu) runs `scripts/launch.sh`,
which is idempotent and safe to click repeatedly:

1. starts Ollama, Postgres, the gateway and Open WebUI (skipping whatever is
   already up)
2. opens the chat UI, the admin UI, and VS Code

A desktop launcher has **no terminal and no shell environment**, so progress
appears as desktop notifications and failures open a dialog with the tail of
`logs/launch.log` — rather than failing silently, which is the usual fate of
scripts run from an icon.

Right-click gives *Open chat UI only*, *Show spend report*, and *Stop
everything*. Change what gets opened in `~/.config/ai-gateway/launch.conf`:

```bash
OPEN_CHAT=1     # browser → chat UI
OPEN_ADMIN=1    # browser → LiteLLM admin/spend UI
OPEN_EDITOR=0   # skip VS Code, e.g. if you only want to chat
```

### Where the API key lives now

The gateway previously relied on `ANTHROPIC_API_KEY` being exported in your
shell. That turned out to be true only in shells where you had typed the
`export` by hand — meaning the gateway could not survive a reboot, and a
desktop icon could never start it at all.

The key now lives in **`~/.config/ai-gateway/secrets.env`** (chmod 600, outside
the repo, gitignored by virtue of not being in it). `scripts/start.sh` sources
it when the variable is unset. Verified: the gateway starts under `env -i` with
no environment whatsoever.

To rotate the key, edit that one file and `make restart`.

## Interfaces

The gateway is only useful through something. What works, and what doesn't:

| Interface | Status | Notes |
|---|---|---|
| **Cline** (VS Code) | configured | The graphical/agentic one. Extension host runs locally, so `127.0.0.1` resolves correctly |
| **Cline** (CLI) | configured | `cline "..."` — verified through the gateway |
| **aider** | configured | `scripts/gw-aider`; `AIDER_MODEL=openai/frontier scripts/gw-aider` to switch tier |
| **Open WebUI** | running on :3000 | Graphical chat, `chat-ui` key, local-first |
| **Claude Code** | works, but read below | `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` |
| **herdr** | already installed | Terminal workspace manager — the Linux answer to cmux |
| **Cursor** | ✗ cannot work | See below |

### Cursor doesn't work, and can't be made to

Cursor routes chat and agent requests through **its own cloud backend**
(`api2.cursor.sh`) before they reach your Base URL. So `http://127.0.0.1:4000`
resolves to Cursor's server's loopback, not yours. The only workaround is a
public tunnel (ngrok/Cloudflare) — which sends every prompt, including the ones
you wanted handled privately by a local model, through a third party. That
defeats the local tier entirely. Tab completion stays on Cursor's models
regardless of the override.

Use **Cline** instead: same in-editor agentic experience, but it talks to the
gateway directly from your machine.

### cmux doesn't run here

cmux is a native **macOS** app (Swift/AppKit on libghostty). Linux is
waitlist-only. `herdr` is already installed and does the same job. Avoid
running two worktree managers against one repo — they conflict.

### Claude Code: a cost warning

Routing Claude Code through the gateway means you stop using your claude.ai
subscription and start paying **metered API rates** for the same work. For
heavy interactive use that is usually a large increase.

Recommendation: leave Claude Code on its subscription, and point the gateway at
everything else — Cline, aider, scripts, cron, apps, embeddings. If you do want
it gatewayed, use the passthrough names (`ANTHROPIC_MODEL=claude-sonnet-5`),
not the tier aliases: Claude Code doesn't recognise `balanced` and will assume a
200k context window.

## Virtual keys

Your real `ANTHROPIC_API_KEY` never leaves this machine. Each consumer gets a
scoped, individually revocable key:

| Key | Models | Budget | For |
|-----|--------|--------|-----|
| `dev-workstation` | everything | $100/30d | your IDE, Claude Code, ad-hoc CLI |
| `app-backend`     | no `frontier` | $50/30d | user-facing product traffic |
| `batch-jobs`      | local + `bulk-cloud` | $10/30d | cron, backfills, CI |
| `chat-ui`         | local + haiku/sonnet | $20/30d | Open WebUI; no frontier — a chat box is where an idle $25/Mtok model drains a budget |
| `sandbox-local`   | local only | $0.01/30d | experiments, new teammates — cannot spend |

Keys are in `keys.env` (chmod 600, gitignored). Re-run `make keys` any time;
it skips aliases that already exist. Add, revoke and re-budget from the UI at
`/ui` (username `admin`, password = `LITELLM_MASTER_KEY` from `.env`).

## Resilience

Routing is configured in `config/config.yaml`:

- **Fallbacks** — if the local backend is down, busy or OOM, `routine` work
  transparently goes to `bulk-cloud` rather than erroring. Verified: with
  Ollama stopped, a `routine` request is answered by `claude-haiku-4-5`.
- **Context-window fallbacks** — a prompt too long for the local 32k window is
  automatically re-routed to a 1M-context cloud model.
- **Retries and cooldowns** — 2 retries, then a failing deployment sits out
  for 60s.

## Cost control

```bash
make spend        # by model, by key, budgets remaining, local vs cloud split
```

Prices for each Claude model are declared in `config/config.yaml` so the ledger
is accurate. Keep them in sync if Anthropic changes pricing.

Two deliberate cost decisions:

- **Background health checks are off.** LiteLLM's background checker sends a
  real billable completion to every deployment on every interval — with 6 cloud
  deployments at 300s that is ~1,700 paid calls a day (~$5–8/month) to observe
  that nothing is wrong. Use `make health` on demand, or `make health-local`
  (free) on a timer.
- **Response caching is available but off.** Uncomment `cache` in
  `config/config.yaml` to stop paying twice for identical prompts in evals,
  CI and retries.

## Operating notes

- **This box is CPU-only** (8 cores, 15 GB RAM, Intel iGPU — Ollama will not
  use it). Expect ~7s for a short `routine` reply once warm, and tens of
  seconds for `routine-code`. A cold model load costs ~60s, so models are kept
  resident for 30 min via a systemd drop-in at
  `~/.config/systemd/user/ollama.service.d/override.conf`.
- **`routine-code` (9 GB) and the cloud tiers can't both be comfortable in
  15 GB** alongside a browser. If the box starts swapping, `ollama stop
  qwen2.5-coder:14b` or lean on `balanced` instead.
- Adding a provider (OpenAI, Gemini, OpenRouter, a second local box) is a
  `model_list` entry plus an env var — clients never change.

## Layout

```
config/config.yaml      routing, tiers, prices, fallbacks   ← the interesting file
scripts/setup.sh        one-time bootstrap
scripts/start|stop.sh   gateway lifecycle
scripts/db.sh           postgres lifecycle (up|down|destroy)
scripts/provision-keys.sh   mint virtual keys
scripts/spend.sh        cost reporting
scripts/health*.sh      health checks (paid / free)
scripts/smoke-test.sh   end-to-end verification
scripts/env.sh          point your shell's tools at the gateway
scripts/setup-clients.sh    configure Cline + aider
scripts/webui.sh        Open WebUI lifecycle (up|down|logs|destroy)
scripts/gw-aider        aider, pre-wired to the gateway
scripts/launch.sh       one-click: start everything + open interfaces
scripts/spend-window.sh spend report in a terminal window
assets/ai-gateway.svg   launcher icon
clients/                OpenAI SDK, Anthropic SDK, Node examples
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Gateway dies on boot, `No module named 'prisma'` | `make setup` (installs + generates the prisma client) |
| `table LiteLLM_SpendLogs does not exist` | `make setup` re-runs `prisma db push` |
| Local tier always answers from cloud | Ollama is down — `systemctl --user start ollama`, then `make health-local` |
| First local call takes ~60s | Cold model load; keep-alive is 30 min after the first call |
| `key not allowed to access model` | Working as intended — that key's allowlist excludes the tier |
| Desktop icon does nothing | Check `logs/launch.log`; ensure the file is executable and trusted (`gio set ~/Desktop/ai-gateway.desktop metadata::trusted true`) |
| Icon works but cloud tiers fail | `~/.config/ai-gateway/secrets.env` is missing or holds a stale key |
| Open WebUI shows no models | Its key is `chat-ui`; check `docker logs open-webui` and that the gateway is up |
| Chat UI reachable from other machines | It shouldn't be — `HOST=127.0.0.1` keeps it on loopback despite `--network host`. Verify with `ss -ltn \| grep 3000` |

## Running it across reboots

`make up` daemonises the gateway, so it survives logging out but not a reboot.
If you want it always-on, install a systemd **user** unit that runs
`.venv/bin/litellm --config config/config.yaml`. One wrinkle worth knowing:
systemd does not inherit your shell environment, so `ANTHROPIC_API_KEY` will
not be visible to it. Either run `systemctl --user import-environment
ANTHROPIC_API_KEY` before starting, or put the key in a chmod-600
`EnvironmentFile`. This setup deliberately does not copy your provider key into
a file on disk — that is the one secret worth keeping in exactly one place.
