#!/usr/bin/env node
// Voiceover A/B report — reads the two arms produced by run-decide.mjs (howlins-vo-off = control,
// howlins-vo-on = the plansVoiceover line ON) and quantifies whether that one brief line changed the
// DECIDE output, separating SIGNAL (a consistent, intended editorial shift) from NOISE (Gemini's
// run-to-run variance at temp 0). Prints a comparison + writes runs/vo-ab-summary.json.
//
//   node vo-ab-report.mjs
//
// The voiceover line predicts: with VO on, keep MORE visually-strong / silent shots (the bed the
// narration plays over), lean less on talking-only filler, and cover more with b-roll. We measure
// exactly those, plus a Jaccard noise-floor (within-arm disagreement vs between-arm shift).

import { readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveCut } from "./resolve-cut.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);
const INDEX_PATH = "runs/howlins/perceive__gemini-2.5-flash__run1/index.json";

const index = JSON.parse(await readFile(p(INDEX_PATH), "utf8"));
const shotById = new Map(index.shots.map((s) => [s.id, s]));
const allIds = index.shots.map((s) => s.id);
const isTalk = (s) => s.scene_type === "talking-head";
const isSilent = (s) => s.has_speech === false;                       // the "weak/silent audio" bed
const isReaction = (s) => s.scene_type === "bite-reaction";
const isVisual = (s) => ["food-closeup", "plating", "ambiance", "wide-shot"].includes(s.scene_type);

const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);
const fmt = (x, d = 1) => (Number.isFinite(x) ? x.toFixed(d) : "?");
const frac = (ids, pred) => {                                          // kept fraction among shots matching pred
  const pool = allIds.filter((id) => pred(shotById.get(id)));
  if (!pool.length) return null;
  return pool.filter((id) => ids.has(id)).length / pool.length;
};
const jaccardDist = (a, b) => {                                        // 1 - |∩|/|∪| over two kept-sets
  const A = new Set(a), B = new Set(b);
  let inter = 0; for (const x of A) if (B.has(x)) inter++;
  const uni = A.size + B.size - inter;
  return uni === 0 ? 0 : 1 - inter / uni;
};

async function loadArm(videoId) {
  const base = p("runs", videoId);
  let cells = [];
  try { cells = (await readdir(base)).filter((d) => d.startsWith("decide__")).sort(); } catch { return null; }
  const runs = [];
  for (const cell of cells) {
    let plan;
    try { plan = JSON.parse(await readFile(join(base, cell, "plan.json"), "utf8")); }
    catch { continue; }                                               // failed run → skip
    const segs = plan.segments ?? [];
    const keptSet = new Set(segs.filter((s) => s.keep).map((s) => s.id));
    const { totalDuration } = resolveCut(plan, index);
    const brollSec = (plan.broll_placements ?? []).reduce((a, b) => a + (b.duration_seconds ?? 0), 0);
    runs.push({
      cell,
      keptSet,
      keptCount: keptSet.size,
      spineLen: (plan.final_edit_order ?? []).length,
      recommended: plan.recommended_duration ?? 0,
      resolved: totalDuration,
      voiceovers: segs.filter((s) => s.voiceover_candidate).length,
      broll: (plan.broll_placements ?? []).length,
      brollSec,
      brollPct: totalDuration ? brollSec / totalDuration : 0,
      trims: segs.filter((s) => s.trim_to_seconds != null).length,
      talkKept: frac(keptSet, isTalk),
      silentKept: frac(keptSet, isSilent),
      reactionKept: frac(keptSet, isReaction),
      visualKept: frac(keptSet, isVisual),
    });
  }
  return runs;
}

function agg(runs) {
  const col = (k) => runs.map((r) => r[k]).filter((x) => x != null);
  const stat = (k) => { const c = col(k); return { mean: mean(c), min: Math.min(...c), max: Math.max(...c) }; };
  return {
    n: runs.length,
    keptCount: stat("keptCount"), spineLen: stat("spineLen"),
    recommended: stat("recommended"), resolved: stat("resolved"),
    voiceovers: stat("voiceovers"), broll: stat("broll"),
    brollPct: stat("brollPct"), trims: stat("trims"),
    talkKept: stat("talkKept"), silentKept: stat("silentKept"),
    reactionKept: stat("reactionKept"), visualKept: stat("visualKept"),
  };
}

// Per-shot keep probability within an arm.
const keepProb = (runs) => {
  const m = new Map(allIds.map((id) => [id, 0]));
  for (const r of runs) for (const id of r.keptSet) m.set(id, m.get(id) + 1);
  for (const id of allIds) m.set(id, runs.length ? m.get(id) / runs.length : 0);
  return m;
};

const off = await loadArm("howlins-vo-off");
const on = await loadArm("howlins-vo-on");
if (!off?.length || !on?.length) {
  console.error("Missing runs. Run:  RUN_CONFIG=config-vo-ab.json node run-decide.mjs   first.");
  process.exit(1);
}

const A = agg(off), B = agg(on);
const pOff = keepProb(off), pOn = keepProb(on);

// Noise floor: mean pairwise Jaccard WITHIN each arm vs BETWEEN arms.
const pairs = (arr) => { const o = []; for (let i = 0; i < arr.length; i++) for (let j = i + 1; j < arr.length; j++) o.push([arr[i], arr[j]]); return o; };
const withinOff = mean(pairs(off).map(([a, b]) => jaccardDist(a.keptSet, b.keptSet)));
const withinOn = mean(pairs(on).map(([a, b]) => jaccardDist(a.keptSet, b.keptSet)));
const between = mean(off.flatMap((a) => on.map((b) => jaccardDist(a.keptSet, b.keptSet))));
const noiseFloor = (withinOff + withinOn) / 2;

// Shots whose keep-probability shifted most (signal candidates).
const shifts = allIds.map((id) => {
  const s = shotById.get(id);
  return { id, delta: pOn.get(id) - pOff.get(id), pOff: pOff.get(id), pOn: pOn.get(id),
           type: s.scene_type, silent: s.has_speech === false, subj: s.depicts_subject, hook: s.hook_score };
}).filter((x) => Math.abs(x.delta) >= 0.4).sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));

// ---- print ----
const L = (label, a, b, d = 1, pct = false) => {
  const av = pct ? `${fmt(a.mean * 100, 0)}%` : fmt(a.mean, d);
  const bv = pct ? `${fmt(b.mean * 100, 0)}%` : fmt(b.mean, d);
  const dv = pct ? `${fmt((b.mean - a.mean) * 100, 0)} pts` : `${b.mean - a.mean >= 0 ? "+" : ""}${fmt(b.mean - a.mean, d)}`;
  console.log(`  ${label.padEnd(26)} ${String(av).padStart(8)}   ${String(bv).padStart(8)}   ${String(dv).padStart(10)}`);
};
console.log(`\n════ VOICEOVER BRIEF-LINE A/B · DECIDE (gemini-2.5-pro) · ${off.length} vs ${on.length} runs ════`);
console.log(`index: ${INDEX_PATH} — 46 shots (23 talking-head, 5 food-closeup, 3 plating, 14 bite-reaction, 1 ambiance)\n`);
console.log(`  ${"metric".padEnd(26)} ${"VO OFF".padStart(8)}   ${"VO ON".padStart(8)}   ${"Δ (on−off)".padStart(10)}`);
console.log("  " + "─".repeat(58));
L("kept shots (of 46)", A.keptCount, B.keptCount);
L("spine length (in order)", A.spineLen, B.spineLen);
L("recommended_duration (s)", A.recommended, B.recommended);
L("resolved duration (s)", A.resolved, B.resolved);
L("b-roll placements", A.broll, B.broll);
L("b-roll coverage", A.brollPct, B.brollPct, 0, true);
L("voiceover_candidates", A.voiceovers, B.voiceovers);
L("trims applied", A.trims, B.trims);
console.log("  " + "─".repeat(58) + "   (scene retention)");
L("talking-head kept", A.talkKept, B.talkKept, 0, true);
L("SILENT-audio shots kept", A.silentKept, B.silentKept, 0, true);
L("bite-reaction kept", A.reactionKept, B.reactionKept, 0, true);
L("food/plating/ambiance kept", A.visualKept, B.visualKept, 0, true);

console.log(`\n  NOISE FLOOR (kept-set Jaccard distance):`);
console.log(`    within VO-OFF runs : ${fmt(withinOff, 3)}   within VO-ON runs : ${fmt(withinOn, 3)}   → noise ≈ ${fmt(noiseFloor, 3)}`);
console.log(`    between arms        : ${fmt(between, 3)}   →  ${between > noiseFloor + 0.02 ? "ABOVE noise (the line moved the edit)" : "within noise (no clear effect)"}`);

console.log(`\n  SHOTS THAT SHIFTED (|Δ keep-prob| ≥ 0.4, consistent across runs):`);
if (!shifts.length) console.log("    (none — no shot's keep decision moved consistently)");
for (const s of shifts) {
  const dir = s.delta > 0 ? "＋kept more w/ VO" : "－dropped w/ VO";
  console.log(`    shot ${String(s.id).padStart(2)} ${s.type.padEnd(13)}${s.silent ? "·silent" : "       "} hook${s.hook}  off ${fmt(s.pOff * 100, 0)}% → on ${fmt(s.pOn * 100, 0)}%   ${dir}  [${s.subj}]`);
}

const summary = {
  model: "gemini-2.5-pro", runsOff: off.length, runsOn: on.length, index: INDEX_PATH,
  aggregates: { off: A, on: B },
  noise: { withinOff, withinOn, between, noiseFloor, aboveNoise: between > noiseFloor + 0.02 },
  shifts,
  perRun: { off, on }.off ? undefined : undefined,
  runsOffRaw: off.map((r) => ({ ...r, keptSet: [...r.keptSet] })),
  runsOnRaw: on.map((r) => ({ ...r, keptSet: [...r.keptSet] })),
};
await writeFile(p("runs", "vo-ab-summary.json"), JSON.stringify(summary, null, 2));
console.log(`\n  → wrote runs/vo-ab-summary.json (full per-run data for a judge pass)\n`);
