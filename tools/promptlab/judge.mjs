#!/usr/bin/env node
// Vela prompt lab — LLM-as-judge, v2 (reliable). The OLD judge showed the model the raw 237s proxy + the
// plan JSON and asked it to IMAGINE the cut → same edit scored 35/95/98. The fix: resolve the plan into a
// LINEAR storyboard (resolve-cut.mjs) — the exact edit as it plays, with spoken words + b-roll inline — and
// judge THAT as text (no video, no imagining). Each cell is graded N times (config.judge.passes) and we
// report the MEDIAN per dimension + MAJORITY would_post + the spread, so one noisy pass can't swing a call.
//
//   set -a; . ./.env; set +a
//   JUDGE_CONFIG=config-decide.json JUDGE_CELLS=decide__ node judge.mjs
//
// Judge model is an INDEPENDENT grader (gemini-2.5-pro) — deliberately not Claude, so it isn't grading its
// own family. Routes through your Supabase→Gemini proxy (text-only `generate`, no upload). The validation
// score (run-decide.mjs) stays the OBJECTIVE backbone; this is the SUBJECTIVE editorial read.

import { readFile, writeFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { generate } from "./lib/gemini.mjs";
import { resolveCut } from "./resolve-cut.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);

const DIMS = ["hook_strength", "retention_pacing", "payoff_verdict", "broll_relevance", "speech_cleanliness", "duration_discipline"];

const JUDGE_SCHEMA = {
  type: "OBJECT",
  properties: {
    dimensions: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          dimension: { type: "STRING", enum: DIMS },
          score: { type: "INTEGER" },
          justification: { type: "STRING" },
        },
        propertyOrdering: ["dimension", "score", "justification"],
        required: ["dimension", "score", "justification"],
      },
    },
    overall: { type: "INTEGER" },
    top_fix: { type: "STRING" },
    would_post_as_is: { type: "BOOLEAN" },
  },
  propertyOrdering: ["dimensions", "overall", "top_fix", "would_post_as_is"],
  required: ["dimensions", "overall", "top_fix", "would_post_as_is"],
};

function judgePrompt(storyboard, durationSeconds, recommendedDuration) {
  return `You are a brutally honest short-form (TikTok/Reels) food-video editor. Below is a RESOLVED STORYBOARD: the exact linear cut as it will play — every shot in order, its on-screen duration, the words spoken over it, and any silent b-roll overlay (marked ⤷). You are NOT imagining an edit or watching raw footage; you are grading THIS finished sequence. Judge it as a viewer scrolling TikTok would experience it.

Score each dimension 1 (terrible) → 5 (excellent). EVERY justification MUST cite specific shot ids from the storyboard (e.g. "shot 44, 7") — no vague statements. Apply the anchors and HARD-FAILS exactly.

- hook_strength — the first ~1.5s (the HOOK shot). 5 = a bold claim, a striking food close-up, or a big reaction with a punchy line that stops the scroll. 3 = watchable but generic opener. 1 = static/silent/slow or a flat list read. HARD-FAIL (≤2) if the first shot opens silent or on a slow establishing/wide shot.
- retention_pacing — does momentum hold with no lulls or repetition? 5 = every shot earns its place, tight, builds. 3 = a couple slack beats. 1 = draggy or repetitive. HARD-FAIL (≤2) if the same dish is tasted twice with both takes kept, or any single talking block clearly overstays.
- payoff_verdict — do the money moments (peak reactions, the rating) land, and does the cut END on the verdict/rating? 5 = money shots land uncovered and it closes on the verdict. 1 = payoff buried or the edit doesn't end on the rating. HARD-FAIL (≤2) if the final shot is not the verdict/rating.
- broll_relevance — does each ⤷ overlay show what's being said, at the right time, WITHOUT covering a reaction face? 5 = relevant, well-timed, faces stay visible on bites/reactions. 1 = irrelevant/blank/covers the payoff. HARD-FAIL (≤2) if any b-roll covers a bite/first_taste/peak_reaction/verdict shot, or its source is a keep:false shot (renders blank — the storyboard flags this).
- speech_cleanliness — do cuts fall at natural pauses, never mid-word/mid-thought? 5 = clean throughout. 1 = choppy/clipped sentences. HARD-FAIL (≤2) if any shown line is cut mid-sentence.
- duration_discipline — is total length sensible for TikTok and near the target (${recommendedDuration ?? "~50"}s)? 5 = tight and on-target. 1 = far over/under or bloated.

Then give overall (0–100), a single most-important top_fix (cite shot ids), and would_post_as_is (would YOU post this exact cut).

Return ONLY the JSON. Here is the storyboard (raw source footage was ${Math.round(durationSeconds)}s):

${storyboard}`;
}

const median = (xs) => { const a = xs.filter((n) => n != null).sort((x, y) => x - y); const n = a.length; return n ? (n % 2 ? a[(n - 1) / 2] : (a[n / 2 - 1] + a[n / 2]) / 2) : null; };

async function main() {
  const cfgPath = process.env.JUDGE_CONFIG || "config.json";
  const cfg = JSON.parse(await readFile(p(cfgPath), "utf8"));
  if (cfg.judge?.enabled === false) { console.log(`judge disabled in ${cfgPath}`); return; }
  const model = cfg.judge?.model ?? "gemini-2.5-pro";
  const passes = cfg.judge?.passes ?? 5;
  const temperature = cfg.judge?.temperature ?? 0.4;
  const cellPrefix = process.env.JUDGE_CELLS || "";

  const rows = [];
  const header = ["video", "cell", ...DIMS.map((d) => `${d}_med`), "overall_med", "overall_min", "overall_max", "postable_rate", "top_fix"];

  for (const video of cfg.videos) {
    const index = JSON.parse(await readFile(p(video.indexPath), "utf8"));
    let cells = [];
    try { cells = (await readdir(p("runs", video.id))).filter((d) => d.startsWith(cellPrefix)).sort(); }
    catch { cells = []; }

    for (const cell of cells) {
      const dir = p("runs", video.id, cell);
      let plan;
      try { plan = JSON.parse(await readFile(join(dir, "plan.json"), "utf8")); }
      catch { console.log(`   • ${cell} … (no plan.json, skipped)`); continue; }

      const { storyboard } = resolveCut(plan, index);
      const prompt = judgePrompt(storyboard, video.durationSeconds ?? index.duration_seconds ?? 0, plan.recommended_duration);
      process.stdout.write(`   • ${cell} … `);

      const results = [];
      for (let k = 0; k < passes; k++) {
        try {
          const res = await generate({ prompt, model, schema: JUDGE_SCHEMA, genConfig: { temperature, seed: 7 + k } });
          results.push(JSON.parse(res.text));
          process.stdout.write("·");
        } catch (e) { process.stdout.write("x"); }
      }
      if (!results.length) { console.log(" ✗ all passes failed"); continue; }

      // Aggregate: median per dimension, spread on overall, majority would_post.
      const dimMed = {};
      for (const d of DIMS) dimMed[d] = median(results.map((j) => (j.dimensions ?? []).find((x) => x.dimension === d)?.score));
      const overalls = results.map((j) => j.overall).filter((n) => n != null);
      const postableRate = results.filter((j) => j.would_post_as_is).length / results.length;
      const aggregate = {
        passes: results.length,
        dimension_medians: dimMed,
        overall_median: median(overalls), overall_min: Math.min(...overalls), overall_max: Math.max(...overalls),
        postable_rate: postableRate,
        top_fixes: results.map((j) => j.top_fix),
      };
      await writeFile(join(dir, "judge.json"), JSON.stringify({ aggregate, passes: results }, null, 2));

      rows.push([video.id, cell, ...DIMS.map((d) => dimMed[d] ?? ""), aggregate.overall_median, aggregate.overall_min, aggregate.overall_max, postableRate.toFixed(2), results[0].top_fix ?? ""]);
      console.log(` overall med ${aggregate.overall_median} [${aggregate.overall_min}–${aggregate.overall_max}] · postable ${(postableRate * 100).toFixed(0)}%`);
    }
  }

  const csvCell = (s) => { const v = String(s ?? ""); return /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v; };
  const csv = [header, ...rows].map((r) => r.map(csvCell).join(",")).join("\n") + "\n";
  await writeFile(p("runs", "summary_judged.csv"), csv);
  console.log(`\n✅ Wrote runs/summary_judged.csv (${rows.length} cells judged ×${passes} passes).`);
}

main().catch((e) => { console.error(e); process.exit(1); });
