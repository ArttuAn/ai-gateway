#!/usr/bin/env node
/**
 * Run a coding agent against this repo inside a throwaway container, driven by
 * LOCAL models through the gateway.
 *
 * Two independent safety nets, which is the point of doing it this way:
 *
 *   1. Sandcastle contains the BLAST RADIUS — the agent works in a container on
 *      a temporary git branch. If it wrecks the tree, the container is deleted
 *      and you discard the branch.
 *   2. The gateway's `sandbox-local` virtual key contains the BILL — it is
 *      allowlisted to local models only with a $0.01 budget, so a runaway loop
 *      cannot reach Opus or spend real money. Belt and braces.
 *
 * Usage:
 *   node sandbox/run.mjs "add a --version flag to scripts/spend.sh"
 *   SANDBOX_MODEL=sealed-local node sandbox/run.mjs "..."  # smaller/faster model
 */
import { run, claudeCode } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

/** Minimal KEY=VALUE reader for .env / keys.env (no shell evaluation). */
function readEnvFile(name) {
  try {
    return Object.fromEntries(
      readFileSync(join(ROOT, name), "utf8")
        .split("\n")
        .map((l) => l.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/))
        .filter(Boolean)
        .map((m) => [m[1], m[2].trim().replace(/^["']|["']$/g, "")]),
    );
  } catch {
    return {};
  }
}

const cfg = { ...readEnvFile(".env"), ...readEnvFile("keys.env") };
const port = cfg.GATEWAY_PORT ?? "4000";
const key = cfg.SANDBOX_LOCAL_KEY;

if (!key && (process.env.SANDBOX_BACKEND ?? "local") === "local") {
  console.error("SANDBOX_LOCAL_KEY missing from keys.env — run: make keys");
  process.exit(1);
}

const prompt = process.argv.slice(2).join(" ").trim();
if (!prompt) {
  console.error('usage: node sandbox/run.mjs "<what the agent should do>"');
  process.exit(1);
}

// ── Backend: who answers the agent's requests ───────────────────────────────
//
//   local        (default) — gateway → Ollama. Free, private, slow on CPU.
//                            Capped by the sandbox-local key: no paid model
//                            is reachable even if the agent goes haywire.
//
//   subscription           — Claude Code's own OAuth token, i.e. YOUR claude.ai
//                            plan. Frontier quality, flat-rate, no per-token
//                            API billing. Mint one on the host with:
//                                claude setup-token
//                            then put it in .sandcastle/.env as
//                                CLAUDE_CODE_OAUTH_TOKEN=...
//
// Critical: ANTHROPIC_API_KEY is never injected into the sandbox. Claude Code
// prefers it over the OAuth token, so a stray key silently converts your
// flat-rate subscription run into a metered API bill.
const backend = process.env.SANDBOX_BACKEND ?? "local";
const branch = `sandbox/${new Date().toISOString().replace(/[:.]/g, "-")}`;

let model, agentEnv, blurb;

if (backend === "subscription") {
  model = process.env.SANDBOX_MODEL ?? "claude-sonnet-5";
  const oauth = readEnvFile(".sandcastle/.env").CLAUDE_CODE_OAUTH_TOKEN;
  if (!oauth) {
    console.error(
      "SANDBOX_BACKEND=subscription needs a token.\n" +
      "  1) on the host:  claude setup-token\n" +
      "  2) add to .sandcastle/.env:  CLAUDE_CODE_OAUTH_TOKEN=<token>",
    );
    process.exit(1);
  }
  agentEnv = { CLAUDE_CODE_OAUTH_TOKEN: oauth };
  blurb = "your claude.ai subscription — flat rate, no per-token billing";
} else {
  model = process.env.SANDBOX_MODEL ?? "sealed-code";
  agentEnv = {
    // Point Claude Code at the gateway instead of Anthropic.
    ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}`,
    ANTHROPIC_AUTH_TOKEN: key,
    // Claude Code assumes a 200k window for model names it doesn't know.
    // The local models are 32k — without this it overflows them, and the
    // oversized request gets bounced to a cloud model this key cannot use.
    CLAUDE_CODE_MAX_CONTEXT_TOKENS: "32000",
    // Claude Code 2.1.x hard-fails (exit 1) on model names it doesn't know —
    // including while generating a session title, before your prompt even
    // runs. Gateway tier names are by definition unknown to it, so this must
    // be set or every local run dies at startup.
    CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT: "1",
    // Local models are slow on CPU; don't let Claude Code give up early.
    BASH_DEFAULT_TIMEOUT_MS: "600000",
  };
  blurb = "sandbox-local key — sealed local tiers, no fallback to paid models";
}

console.log(`agent  : claude-code on "${model}" (${backend})`);
console.log(`branch : ${branch}`);
console.log(`billing: ${blurb}\n`);

const result = await run({
  agent: claudeCode(model, { env: agentEnv }),
  // --network host is REQUIRED: the gateway listens on 127.0.0.1, and a
  // bridged container cannot reach the host loopback (verified: HTTP 000).
  // Filesystem isolation — the part that protects your repo — is unaffected.
  sandbox: docker({ network: "host" }),
  prompt,
  maxIterations: Number(process.env.SANDBOX_MAX_ITERATIONS ?? 1),
  branchStrategy: { type: "branch", branch },
  idleTimeoutSeconds: Number(process.env.SANDBOX_IDLE_TIMEOUT ?? 900),
  logging: { type: "stdout", verbose: process.env.SANDBOX_VERBOSE === "1" },
});

console.log("\n─── result ───────────────────────────────");
console.log(`branch  : ${result.branch}`);
console.log(`commits : ${result.commits?.length ?? 0}`);
for (const c of result.commits ?? []) console.log(`  ${c.sha}`);
console.log(`\nreview with:  git log -p ${result.branch}`);
console.log(`discard with: git branch -D ${result.branch}`);
