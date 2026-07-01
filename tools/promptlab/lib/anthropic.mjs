// Claude DECIDE for the lab — TEXT-ONLY, to A/B against Gemini. TWO ways to reach Claude:
//   1. ANTHROPIC_API_KEY set → the real Messages API with FORCED tool-use (production-grade, schema-enforced).
//   2. No key → drive Claude HEADLESSLY through the local Claude Code CLI (`claude -p`), which uses the user's
//      existing Claude Code subscription — NO separate API key/billing needed, perfect for testing.
// Zero deps (Node 18+ global fetch + child_process).

import { spawn } from "node:child_process";
import { tmpdir } from "node:os";

const API = "https://api.anthropic.com/v1/messages";

/** Drive Claude headlessly via the Claude Code CLI (`claude -p`). Runs from a NEUTRAL cwd (tmp) so it doesn't
 *  pick up the Vela project's CLAUDE.md. Returns raw stdout (the caller strips fences + extracts the JSON). */
function claudeCli({ prompt, model, timeoutMs, thinkingBudget }) {
  return new Promise((resolve, reject) => {
    // A "<model>-nothink" label runs that model with extended thinking DISABLED (MAX_THINKING_TOKENS=0) —
    // ~10× faster via `claude -p` (347s → 34s). Lets us A/B thinking-on vs thinking-off in one config.
    // A numeric thinkingBudget sets MAX_THINKING_TOKENS to that value (for the budget A/B via the CLI path).
    const noThink = model.endsWith("-nothink");
    const realModel = noThink ? model.slice(0, -"-nothink".length) : model;
    const budgetEnv = noThink ? "0" : (thinkingBudget != null ? String(thinkingBudget) : null);
    const env = budgetEnv != null ? { ...process.env, MAX_THINKING_TOKENS: budgetEnv } : process.env;
    const child = spawn("claude", ["-p", "--model", realModel], { cwd: tmpdir(), env, stdio: ["pipe", "pipe", "pipe"] });
    let out = "", err = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("claude -p timed out")); }, timeoutMs);
    child.on("error", (e) => { clearTimeout(timer); reject(e); });
    child.on("close", (code) => { clearTimeout(timer); code === 0 ? resolve(out) : reject(new Error(`claude -p exit ${code}: ${err.slice(0, 300)}`)); });
    child.stdin.write(prompt + "\n\nReturn ONLY the decisions JSON object — no prose, no markdown, no explanation.");
    child.stdin.end();
  });
}

/** Convert the lab's Gemini-style schema (UPPERCASE "type", propertyOrdering) → standard JSON Schema. */
export function toJsonSchema(s) {
  if (Array.isArray(s)) return s.map(toJsonSchema);
  if (s && typeof s === "object") {
    const out = {};
    for (const [k, v] of Object.entries(s)) {
      if (k === "propertyOrdering") continue;                 // Gemini-only ordering hint — drop
      if (k === "type" && typeof v === "string") { out.type = v.toLowerCase(); continue; }
      out[k] = toJsonSchema(v);
    }
    return out;
  }
  return s;
}

/** Run a text-only DECIDE on Claude; returns { text, httpMs } where text is the decisions JSON (stringified). */
export async function decide({ prompt, schema, model, thinkingBudget, maxTokens = 8192, timeoutMs = 700_000 }) {
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) {
    // No API key → drive Claude through the local Claude Code CLI (uses the existing subscription, no key).
    const t0 = Date.now();
    const out = await claudeCli({ prompt, model, timeoutMs, thinkingBudget });
    return { text: out, httpMs: Date.now() - t0 };
  }
  // Extended thinking (budget A/B) is INCOMPATIBLE with forced tool use → when a budget is set we use
  // tool_choice:auto + a `thinking` block (mirrors supabase/functions/gemini-proxy callAnthropicCore, i.e.
  // the exact production call). With no budget we keep the old forced-tool path (schema-guaranteed output).
  const useThinking = thinkingBudget != null && thinkingBudget > 0;
  const budget = useThinking ? Math.max(1024, thinkingBudget) : 0;
  const tool = { name: "emit_decisions", description: "Return ONLY the edit decisions object.", input_schema: toJsonSchema(schema) };
  const body = useThinking
    ? { model, max_tokens: budget + 8192, thinking: { type: "enabled", budget_tokens: budget }, tools: [tool], tool_choice: { type: "auto" }, messages: [{ role: "user", content: prompt }] }
    : { model, max_tokens: maxTokens, tools: [tool], tool_choice: { type: "tool", name: "emit_decisions" }, messages: [{ role: "user", content: prompt }] };
  const t0 = Date.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(API, {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: ctrl.signal,
    });
    const text = await r.text();
    if (!r.ok) throw new Error(`anthropic HTTP ${r.status}: ${text.slice(0, 300)}`);
    const data = JSON.parse(text);
    const toolUse = (data.content || []).find((c) => c.type === "tool_use");
    if (toolUse) return { text: JSON.stringify(toolUse.input), httpMs: Date.now() - t0, usage: data.usage ?? null };
    // With thinking + auto, Claude may answer in a text block instead of calling the tool — accept that
    // (the caller's stripFences pulls the JSON out). Only fail if there's truly nothing.
    const textOut = (data.content || []).filter((c) => c.type === "text").map((c) => c.text ?? "").join("");
    if (textOut) return { text: textOut, httpMs: Date.now() - t0, usage: data.usage ?? null };
    throw new Error(`anthropic returned no tool_use or text: ${text.slice(0, 300)}`);
  } finally {
    clearTimeout(timer);
  }
}
