#!/usr/bin/env node
// PERCEIVE → DECIDE: the editor. TEXT-ONLY (no video). Reads a locked PERCEIVE index + the creator's
// style+brief (sliced from the bundle's prompt.txt) → DECIDE decisions → adaptToEditPlan → a full EditPlan
// scored by the EXISTING `validate.mjs`. Writes runs/<id>/decide__<model>__run<i>/
// {raw,decisions,plan,adapt-warnings,validation,timing}.json + runs/summary_decide.csv. Then grade the
// plan.json files with `JUDGE_CONFIG=config-decide.json node judge.mjs` (the editorial judge — the RIGHT
// tool for DECIDE, unlike the noisy perception judge).
//
//   SUPABASE_PROJECT_REF=... SUPABASE_ANON_KEY=... node run-decide.mjs

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { generate } from "./lib/gemini.mjs";
import * as anthropic from "./lib/anthropic.mjs";
import { validatePlan } from "./lib/validate.mjs";
import { adaptToEditPlan } from "./adapt-plan.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);
const MARKER = "=== AUDIO TRANSCRIPT — GROUND TRUTH FOR TIMING ===";

/** Style profile + brief = everything in the bundle's prompt.txt BEFORE the transcript marker. */
async function styleBrief(dir) {
  try {
    const full = await readFile(p(dir, "prompt.txt"), "utf8");
    const i = full.indexOf(MARKER);
    const slice = (i > 0 ? full.slice(0, i) : "").trim();
    if (slice) return slice;
  } catch { /* none */ }
  return "(No active style profile or brief for this run — use good general short-form food-video judgement. NOTE: a stubbed run is NOT a fair style A/B.)";
}

function stripFences(s) {
  s = String(s).trim();
  if (s.startsWith("```")) { const nl = s.indexOf("\n"); if (nl >= 0) s = s.slice(nl + 1); const c = s.lastIndexOf("```"); if (c >= 0) s = s.slice(0, c); s = s.trim(); }
  const a = s.indexOf("{"), b = s.lastIndexOf("}");
  return a >= 0 && b > a ? s.slice(a, b + 1) : s;
}

const csvCell = (s) => { const x = String(s ?? ""); return /[",\n]/.test(x) ? `"${x.replace(/"/g, '""')}"` : x; };
const top = (vs) => { const m = {}; for (const x of vs) m[x.kind] = (m[x.kind] || 0) + 1; return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k, n]) => `${k}×${n}`).join(" "); };

async function main() {
  const cfg = JSON.parse(await readFile(p(process.env.RUN_CONFIG || "config-decide.json"), "utf8"));
  const decideBody = await readFile(p("prompts", "decide.txt"), "utf8");
  const schema = JSON.parse(await readFile(p("decide-schema.json"), "utf8"));
  const models = cfg.models ?? ["gemini-2.5-flash"];
  const N = cfg.runs ?? 1;
  const rows = [];
  const header = ["video", "model", "run", "score", "violations", "topViolations", "adaptWarnings", "segments", "kept", "broll", "orderLen", "httpMs"];

  for (const video of cfg.videos) {
    const dir = video.dir ?? `fixtures/${video.id}`;
    const index = JSON.parse(await readFile(p(video.indexPath), "utf8"));
    const sb = await styleBrief(dir);
    const prompt = `${sb}\n\n${decideBody}\n\n=== CONTENT INDEX ===\n${JSON.stringify(index)}`;
    console.log(`\n🎬 ${video.id} — DECIDE on ${video.indexPath} (${index.shots?.length} shots, ${index.talk_spans?.length} spans); style+brief ${sb.length} chars`);

    for (const entry of models) {
      // A model entry is either a bare id string or { model, thinkingBudget, label } (for the budget A/B).
      const spec = typeof entry === "string" ? { model: entry } : entry;
      const { model, thinkingBudget } = spec;
      const cellName = spec.label ?? model;
      for (let i = 1; i <= N; i++) {
        const label = `decide__${cellName}__run${i}`;
        const outDir = p("runs", video.id, label);
        await mkdir(outDir, { recursive: true });
        process.stdout.write(`   • ${label}${thinkingBudget ? ` (think ${thinkingBudget})` : ""} … `);
        try {
          // DECIDE is text-only → route by provider: claude-* → Anthropic, else Gemini (via the proxy).
          const res = model.startsWith("claude")
            ? await anthropic.decide({ prompt, schema, model, thinkingBudget })
            : await generate({ prompt, model, schema });
          await writeFile(join(outDir, "raw.json"), res.text);
          await writeFile(join(outDir, "timing.json"), JSON.stringify({ httpMs: res.httpMs }, null, 2));

          let decisions, plan, warnings = [], report, err = null;
          try {
            decisions = JSON.parse(stripFences(res.text));
            ({ plan, warnings } = adaptToEditPlan(index, decisions));
            report = validatePlan(plan, video.durationSeconds ?? 0);
          } catch (e) { err = e.message; }
          if (decisions) await writeFile(join(outDir, "decisions.json"), JSON.stringify(decisions, null, 2));
          if (plan) await writeFile(join(outDir, "plan.json"), JSON.stringify(plan, null, 2));
          if (warnings.length) await writeFile(join(outDir, "adapt-warnings.json"), JSON.stringify(warnings, null, 2));
          if (report) await writeFile(join(outDir, "validation.json"), JSON.stringify(report, null, 2));

          rows.push([video.id, cellName, i,
            report ? report.score.toFixed(2) : "", report ? report.violations.length : "",
            report ? top(report.violations) : (err ? "PARSE_FAIL" : ""),
            warnings.length, report ? report.segmentCount : "", report ? report.keptCount : "",
            plan ? plan.broll_placements.length : "", plan ? plan.final_edit_order.length : "", res.httpMs]);
          console.log(report
            ? `score ${report.score.toFixed(2)} (${report.violations.length} viol · ${warnings.length} adapt-warn · ${plan.final_edit_order.length} in order · ${plan.broll_placements.length} broll)`
            : `⚠️ ${err}`);
        } catch (e) {
          await writeFile(join(outDir, "error.txt"), e.message);
          rows.push([video.id, cellName, i, "", "", "ERROR", "", "", "", "", "", ""]);
          console.log(`✗ ${e.message}`);
        }
      }
    }
  }

  const csv = [header, ...rows].map((r) => r.map(csvCell).join(",")).join("\n") + "\n";
  await writeFile(p("runs", "summary_decide.csv"), csv);
  console.log(`\n✅ Wrote runs/summary_decide.csv (${rows.length} runs). Next: JUDGE_CONFIG=config-decide.json node judge.mjs`);
}

main().catch((e) => { console.error(e); process.exit(1); });
