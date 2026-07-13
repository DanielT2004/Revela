#!/usr/bin/env node
// Voiceover A/B judge — the EDITORIAL grading system for the plansVoiceover brief-line test.
//
// Why the existing judge.mjs can't grade this A/B: its rubric assumes a SPEECH-LED edit (spoken story,
// b-roll under speech). A cut produced with "creator will narrate in post" is SUPPOSED to carry less
// in-footage talking — grading it speech-led punishes it for succeeding. So this judge is mode-aware:
//
//   PART 1 — ABSOLUTE (each cut vs its own goal), 1–5 per dimension, N passes, medians:
//     shared core (both arms):
//       • scroll_stop_hook   — first ~1.5s stops the scroll (bold claim / striking food / big reaction)
//       • retention_pacing   — momentum holds; every shot earns its place; no lulls or repeats
//       • payoff_landing     — peak reactions + the verdict land uncovered; cut ENDS on the verdict
//       • duration_discipline— sensible for TikTok and near the ~50s target
//     VO-OFF only (speech-led edit, posted as-is):
//       • spoken_story       — in-footage speech tells a complete story (place → dishes → verdict), no mid-thought cuts
//       • broll_support      — overlays show what's being said; never cover a reaction face
//     VO-ON only (a BED for narration the creator records afterward):
//       • narration_headroom — in-footage speech reduced to essential punchy moments a narration can be
//                              mixed around; no long talking runs that would FIGHT the narration
//       • visual_bed_quality — watchable muted: visual variety/beauty/sequence logic carries the video
//
//   PART 2 — BLINDED PAIRWISE (the actual A/B verdict): matched off/on pairs shown as "Cut A"/"Cut B"
//   (order swapped across passes), judge answers: which posts better AS-IS (speech-led), which is the
//   better NARRATION BED, and how editorially different they are (0–10). If the toggle works, OFF wins
//   as-is, ON wins bed — same-cut-wins-both or coin-flips mean the line does nothing.
//
//   set -a; . ./.env; set +a
//   node vo-judge.mjs            → runs/vo-judge.json + console verdict
//
// Judge model: gemini-pro-latest (2.5-pro is retired). Independent grader via the Supabase proxy.

import { readFile, writeFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { generate } from "./lib/gemini.mjs";
import { resolveCut } from "./resolve-cut.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);

const MODEL = "gemini-pro-latest";
const PASSES = 3;                    // per absolute cell and per pair
const INDEX_PATH = "runs/howlins/perceive__gemini-2.5-flash__run1/index.json";
const CELL_PREFIX = "decide__gemini-pro-latest__";   // only the comparable-model cells
const TARGET_S = 50;

const CORE = ["scroll_stop_hook", "retention_pacing", "payoff_landing", "duration_discipline"];
const OFF_DIMS = [...CORE, "spoken_story", "broll_support"];
const ON_DIMS = [...CORE, "narration_headroom", "visual_bed_quality"];

const absSchema = (dims) => ({
  type: "OBJECT",
  properties: {
    dimensions: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          dimension: { type: "STRING", enum: dims },
          score: { type: "INTEGER" },
          justification: { type: "STRING" },
        },
        propertyOrdering: ["dimension", "score", "justification"],
        required: ["dimension", "score", "justification"],
      },
    },
    overall: { type: "INTEGER" },
    top_fix: { type: "STRING" },
    would_post: { type: "BOOLEAN" },
  },
  propertyOrdering: ["dimensions", "overall", "top_fix", "would_post"],
  required: ["dimensions", "overall", "top_fix", "would_post"],
});

const PAIR_SCHEMA = {
  type: "OBJECT",
  properties: {
    better_as_is: { type: "STRING", enum: ["A", "B"] },
    better_as_is_reason: { type: "STRING" },
    better_narration_bed: { type: "STRING", enum: ["A", "B"] },
    better_narration_bed_reason: { type: "STRING" },
    editorial_difference_0_10: { type: "INTEGER" },
    key_differences: { type: "STRING" },
  },
  propertyOrdering: ["better_as_is", "better_as_is_reason", "better_narration_bed", "better_narration_bed_reason", "editorial_difference_0_10", "key_differences"],
  required: ["better_as_is", "better_as_is_reason", "better_narration_bed", "better_narration_bed_reason", "editorial_difference_0_10", "key_differences"],
};

const PERSONA = `You are a brutally honest TikTok/Reels food-content editor and virality strategist. You judge finished cuts the way a scrolling viewer experiences them: the first 1.5 seconds decide everything, momentum must never sag, and the money moments (peak reactions, the rating) must land uncovered. You are reading a RESOLVED STORYBOARD — the exact linear cut as it will play: every shot in order, its on-screen duration, the words spoken over it, and any silent b-roll overlay (⤷ lines). You are NOT imagining an edit and NOT watching raw footage; grade THIS sequence only. Every justification MUST cite specific shot ids.`;

function offPrompt(storyboard) {
  return `${PERSONA}

This cut will be posted AS-IS — the in-footage speech is the whole story. Score 1 (terrible) → 5 (excellent):

- scroll_stop_hook — the first ~1.5s. 5 = bold claim / striking close-up / big reaction with a punchy line. HARD-FAIL (≤2) if it opens silent, slow, or on a flat establishing shot.
- retention_pacing — momentum with no lulls. HARD-FAIL (≤2) if a dish is tasted twice with both takes kept, or one talking block clearly overstays.
- payoff_landing — peak reactions + rating land uncovered, cut ENDS on the verdict. HARD-FAIL (≤2) if the final shot is not the verdict/rating.
- duration_discipline — near ~${TARGET_S}s and tight for TikTok.
- spoken_story — the speech alone tells a complete story: where we are, what's ordered, reactions, verdict — no mid-thought cuts, no orphaned fragments (a line whose setup was cut).
- broll_support — every ⤷ overlay shows what's being said at that moment and never covers a bite/reaction/verdict face.

Then overall (0–100), the single most important top_fix (cite shot ids), and would_post (post this exact cut as-is?).
Return ONLY the JSON.

${storyboard}`;
}

function onPrompt(storyboard) {
  return `${PERSONA}

CONTEXT: this cut is a NARRATION BED. The creator will record a fresh voiceover over the finished edit (Vela ducks original audio to ~20% under the narration; the in-footage speech that remains is meant to poke through only at key moments). Grade the cut FOR THAT PURPOSE — do NOT penalize it for having less spoken story; penalize it when in-footage talking would FIGHT a narration. Score 1 (terrible) → 5 (excellent):

- scroll_stop_hook — the first ~1.5s, judged visually-first (a striking food shot or big reaction works even before narration lands). HARD-FAIL (≤2) if it opens on a flat, low-energy shot.
- retention_pacing — visual momentum with no lulls. HARD-FAIL (≤2) if a dish repeats with both takes kept or any single block overstays.
- payoff_landing — the peak reactions + rating moments still land on-screen and the cut ENDS on the verdict beat. HARD-FAIL (≤2) if it doesn't end on the verdict.
- duration_discipline — near ~${TARGET_S}s and tight.
- narration_headroom — how well a fresh narration mixes over this: in-footage speech is reduced to short, essential, punchy moments (real reactions, one-liners, the verdict) that narration can be written around; long explanatory talking runs = the narration and the footage talk over each other = low score.
- visual_bed_quality — watch it MUTED in your head: do the visuals alone carry a coherent, appetizing sequence (variety, beauty shots, food action), or is it wall-to-wall faces talking?

Then overall (0–100), the single most important top_fix (cite shot ids), and would_post (after recording a good narration over it, would you post?).
Return ONLY the JSON.

${storyboard}`;
}

function pairPrompt(sbA, sbB) {
  return `${PERSONA}

Below are TWO alternative cuts (Cut A, Cut B) of the SAME raw footage. Answer BOTH questions, each with a one-sentence reason citing shot ids:

1) better_as_is — which cut is the stronger TikTok posted AS-IS, speech-led, no added narration?
2) better_narration_bed — which cut is the stronger BED for a fresh narration voiceover recorded over it afterward (original audio ducked under the voice; visuals + brief speech moments carry it)?

Also rate editorial_difference_0_10 — how differently edited these two cuts are (0 = essentially the same cut, 10 = radically different keep/order/coverage decisions), and summarize key_differences in one sentence.
Return ONLY the JSON.

=== CUT A ===
${sbA}

=== CUT B ===
${sbB}`;
}

const median = (xs) => { const a = xs.filter((n) => n != null).sort((x, y) => x - y); const n = a.length; return n ? (n % 2 ? a[(n - 1) / 2] : (a[n / 2 - 1] + a[n / 2]) / 2) : null; };
const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

async function loadCells(videoId, index) {
  const base = p("runs", videoId);
  const cells = (await readdir(base)).filter((d) => d.startsWith(CELL_PREFIX)).sort();
  const out = [];
  for (const cell of cells) {
    try {
      const plan = JSON.parse(await readFile(join(base, cell, "plan.json"), "utf8"));
      out.push({ cell, plan, storyboard: resolveCut(plan, index).storyboard });
    } catch { /* failed run — skip */ }
  }
  return out;
}

async function judgeAbsolute(entry, mode) {
  const dims = mode === "on" ? ON_DIMS : OFF_DIMS;
  const prompt = mode === "on" ? onPrompt(entry.storyboard) : offPrompt(entry.storyboard);
  const passes = [];
  for (let k = 0; k < PASSES; k++) {
    try {
      const res = await generate({ prompt, model: MODEL, schema: absSchema(dims), genConfig: { temperature: 0.4, seed: 11 + k } });
      passes.push(JSON.parse(res.text));
      process.stdout.write("·");
    } catch { process.stdout.write("x"); }
  }
  const dimMed = {};
  for (const d of dims) dimMed[d] = median(passes.map((j) => (j.dimensions ?? []).find((x) => x.dimension === d)?.score));
  const overalls = passes.map((j) => j.overall).filter((n) => n != null);
  return {
    cell: entry.cell, mode, passes,
    dimension_medians: dimMed,
    overall_median: median(overalls),
    would_post_rate: passes.length ? passes.filter((j) => j.would_post).length / passes.length : 0,
    top_fixes: passes.map((j) => j.top_fix),
  };
}

async function judgePair(off, on, pairIdx) {
  const votes = [];
  for (let k = 0; k < PASSES; k++) {
    const flipped = (pairIdx + k) % 2 === 1;            // swap A/B across passes → position-bias control
    const [A, B] = flipped ? [on, off] : [off, on];
    const unflip = (side) => (flipped ? (side === "A" ? "on" : "off") : (side === "A" ? "off" : "on"));
    try {
      const res = await generate({ prompt: pairPrompt(A.storyboard, B.storyboard), model: MODEL, schema: PAIR_SCHEMA, genConfig: { temperature: 0.4, seed: 23 + k } });
      const j = JSON.parse(res.text);
      votes.push({
        as_is: unflip(j.better_as_is), as_is_reason: j.better_as_is_reason,
        bed: unflip(j.better_narration_bed), bed_reason: j.better_narration_bed_reason,
        difference: j.editorial_difference_0_10, key_differences: j.key_differences, flipped,
      });
      process.stdout.write("·");
    } catch { process.stdout.write("x"); }
  }
  const maj = (k) => { const c = votes.filter((v) => v[k] === "on").length; return c > votes.length / 2 ? "on" : c < votes.length / 2 ? "off" : "tie"; };
  return { pair: `${off.cell} vs ${on.cell}`, votes, as_is_winner: maj("as_is"), bed_winner: maj("bed"), difference_median: median(votes.map((v) => v.difference)) };
}

async function main() {
  const index = JSON.parse(await readFile(p(INDEX_PATH), "utf8"));
  const offCells = await loadCells("howlins-vo-off", index);
  const onCells = await loadCells("howlins-vo-on", index);
  if (!offCells.length || !onCells.length) { console.error("Missing arm runs — run the A/B first."); process.exit(1); }
  console.log(`VO judge — ${offCells.length} off / ${onCells.length} on cells · ${PASSES} passes · judge ${MODEL}\n`);

  // PART 1 — absolute, mode-aware
  const absolute = [];
  for (const e of offCells) { process.stdout.write(`  abs OFF ${e.cell} `); absolute.push(await judgeAbsolute(e, "off")); console.log(` → ${absolute.at(-1).overall_median}`); }
  for (const e of onCells) { process.stdout.write(`  abs ON  ${e.cell} `); absolute.push(await judgeAbsolute(e, "on")); console.log(` → ${absolute.at(-1).overall_median}`); }

  // PART 2 — blinded matched pairs
  const pairs = [];
  const nPairs = Math.min(offCells.length, onCells.length);
  for (let i = 0; i < nPairs; i++) {
    process.stdout.write(`  pair ${i + 1}/${nPairs} `);
    pairs.push(await judgePair(offCells[i], onCells[i], i));
    const pr = pairs.at(-1);
    console.log(` → as-is: ${pr.as_is_winner} · bed: ${pr.bed_winner} · diff ${pr.difference_median}/10`);
  }

  // ---- aggregate verdict ----
  const arm = (m) => absolute.filter((a) => a.mode === m);
  const armOverall = (m) => median(arm(m).map((a) => a.overall_median));
  const dimTable = (m, dims) => Object.fromEntries(dims.map((d) => [d, median(arm(m).map((a) => a.dimension_medians[d]))]));
  const wins = (k) => ({ off: pairs.filter((p) => p[k] === "off").length, on: pairs.filter((p) => p[k] === "on").length, tie: pairs.filter((p) => p[k] === "tie").length });
  const asIs = wins("as_is_winner"), bed = wins("bed_winner");
  const diffMed = median(pairs.map((p) => p.difference_median));

  const verdict = {
    model: MODEL, passes: PASSES,
    absolute: {
      off: { overall_median: armOverall("off"), dims: dimTable("off", OFF_DIMS), would_post: mean(arm("off").map((a) => a.would_post_rate)) },
      on: { overall_median: armOverall("on"), dims: dimTable("on", ON_DIMS), would_post: mean(arm("on").map((a) => a.would_post_rate)) },
    },
    pairwise: { as_is_wins: asIs, narration_bed_wins: bed, editorial_difference_median: diffMed },
    per_cell: absolute.map(({ passes, ...rest }) => rest),
    pairs,
  };
  await writeFile(p("runs", "vo-judge.json"), JSON.stringify({ verdict, absolute_full: absolute }, null, 2));

  console.log(`\n════ EDITORIAL VERDICT ════`);
  console.log(`ABSOLUTE (each arm vs its own goal, overall median):  OFF ${verdict.absolute.off.overall_median}  ·  ON ${verdict.absolute.on.overall_median}`);
  console.log(`  OFF dims: ${JSON.stringify(verdict.absolute.off.dims)}`);
  console.log(`  ON  dims: ${JSON.stringify(verdict.absolute.on.dims)}`);
  console.log(`PAIRWISE (blinded, ${nPairs} matched pairs, majority of ${PASSES}):`);
  console.log(`  better AS-IS (speech-led): OFF ${asIs.off} · ON ${asIs.on} · tie ${asIs.tie}`);
  console.log(`  better NARRATION BED:      OFF ${bed.off} · ON ${bed.on} · tie ${bed.tie}`);
  console.log(`  editorial difference:      ${diffMed}/10`);
  console.log(`\nToggle WORKS if: OFF wins as-is, ON wins bed, difference ≥ ~3. Same-winner-both or diff ≤ 1 → the line isn't doing its job.`);
  console.log(`→ wrote runs/vo-judge.json`);
}

main().catch((e) => { console.error(e); process.exit(1); });
