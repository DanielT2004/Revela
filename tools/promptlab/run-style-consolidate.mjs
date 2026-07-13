// Consolidation eval — feeds N per-video style profiles to the consolidation prompt (text-only, with the
// seen_in responseSchema, exactly like StyleConsolidator.swift) and checks the merged profile
// deterministically. Runs WITHOUT any video fixture: `--synthetic` fabricates a controlled 3-source set
// with known divergences, so evidence integrity is testable in one command.
//
//   node run-style-consolidate.mjs --synthetic          # the built-in divergence/suppression cases
//   node run-style-consolidate.mjs runA/profile.json runB/profile.json [runC/profile.json]
//
// Deterministic checks (review-hardened): parses · seen_in present + indices in range · divergent line
// evidence == 1 · consistent sign-off evidence == N · suppressed line absent even as a PARAPHRASE ·
// no duplicate normalized quotes · numerics within min/max of inputs · reveal_script numerically honest.
//
// LOCKSTEP: prompts/style-consolidate.txt must equal StyleConsolidator.promptBody — hard-fails on drift.

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { generate } from "./lib/gemini.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const MODEL = process.env.MODEL ?? "gemini-pro-latest";

async function assertLockstep() {
  const swift = await readFile(join(here, "../../FoodEditor/Services/StyleConsolidator.swift"), "utf8");
  const m = swift.match(/static let promptBody = """\n([\s\S]*?)\n {4}"""/);
  if (!m) throw new Error("lockstep: couldn't extract promptBody from StyleConsolidator.swift");
  const fromSwift = m[1].split("\n").map((l) => l.replace(/^ {4}/, "")).join("\n").trim();
  const fromFile = (await readFile(join(here, "prompts/style-consolidate.txt"), "utf8")).trim();
  if (fromSwift !== fromFile)
    throw new Error("lockstep: prompts/style-consolidate.txt is OUT OF DATE vs StyleConsolidator.promptBody — re-extract it (see README).");
}

// ---------------------------------------------------------------------------
// synthetic fixture — 3 profiles with controlled divergence
function syntheticProfiles() {
  const base = (over) => ({
    style_brief: "Duo hosts review food with fast cuts, synchronized bites, and a joint rating.",
    video_format: { type: "single-dish-review", type_custom: null, notes: "duo review of one restaurant order" },
    hook: { type: "talking-head-claim", type_custom: null, opens_within_seconds: 2, has_text_overlay: false,
            description: "both hosts tease the spot", montage: { is_montage: false, source: null, clip_count_estimate: 0, avg_clip_seconds: 0 } },
    pacing: { total_length_seconds: 30, average_clip_length_seconds: 1.8, cut_style: "fast-punchy", cut_style_custom: null, pacing_notes: "quick alternating cuts" },
    voiceover_vs_oncamera: { primary_mode: "mostly-talking-to-camera", primary_mode_custom: null, voiceover_ratio: 0.2, talks_to_camera: true, notes: "faces on camera most of the time" },
    broll: { amount: "moderate", usage: "accent-only", usage_custom: null, favored_shots: ["food-closeup"], notes: "close-ups between reactions" },
    structure: { arc: ["hook", "order", "tasting", "verdict"], sections: [
      { section: "intro", purpose: "set up the spot", beats: [{ label: "introduce restaurant", time_hint: "0-2s", example: "" }] },
      { section: "middle", purpose: "taste and react", beats: [{ label: "taste each item one at a time", time_hint: "4-24s", example: "chicken skin, then thigh" }] },
      { section: "end", purpose: "wrap with a score", beats: [{ label: "numerical rating", time_hint: "26-30s", example: "" }, { label: "signature sign-off", time_hint: "30-32s", example: "" }] }
    ], notes: "hook then per-item tasting then joint verdict" },
    text_and_graphics: { uses_text_overlays: false, text_style: "none", text_style_custom: null, amount: "minimal" },
    audio: { bed: "natural-ambient-sound", bed_custom: null, keeps_natural_food_sounds: true, notes: "crunch is featured" },
    closing: { type: "rating", type_custom: null, description: "joint score then the sign-off" },
    verbal_style: {
      tone: "hyped duo banter", pov: "duo-banter",
      rating_format: "a joint rating out of 10, spoken with a decimal", rating_scope: "overall",
      signoff: "we'll see you in the next one",
      recurring_lines: [
        { quote: "we'll see you in the next one", where_used: "sign-off", medium: "spoken", pattern: null, position: "closing", delivery_note: "said together to camera", likely_habit: 0.9 },
      ],
    },
    habit_candidates: [
      { label: "Synchronized bite with co-host", detail: "Both hosts bite at the same moment", kind: "visual-effect", likely_habit: 0.9, times_seen_in_video: 2 },
      { label: "Let the crunch play", detail: "Bite shots stay uncovered so the crunch is heard", kind: "selection", likely_habit: 0.8, times_seen_in_video: 3 },
    ],
    reveal_script: ["You never review alone — you two trade reactions in sync.", "\"we'll see you in the next one\" — that's how you close."],
    signature_moves: [{ move: "synchronized bite", likely_habit: 0.9 }],
    anything_unusual: null,
    scene_types_present: ["talking-head", "food-closeup", "bite-reaction"],
    confidence: 0.9,
    ...over,
  });

  const p0 = base({});
  // source 0 ONLY: a divergent hook line — consolidated evidence MUST be 1.
  p0.verbal_style = structuredClone(p0.verbal_style);
  p0.verbal_style.recurring_lines = [
    ...p0.verbal_style.recurring_lines,
    { quote: "is this spot worth the hype?", where_used: "hook", medium: "spoken", pattern: null, position: "opening", delivery_note: "asked to camera", likely_habit: 0.6 },
  ];

  const p1 = base({});
  p1.pacing = { ...p1.pacing, total_length_seconds: 34, average_clip_length_seconds: 2.0 };
  // source 1: sign-off PARAPHRASED — semantic dedupe must still count it.
  p1.verbal_style = structuredClone(p1.verbal_style);
  p1.verbal_style.signoff = "see y'all in the next one";
  p1.verbal_style.recurring_lines[0].quote = "see y'all in the next one";
  // source 1 + 2: a paraphrase of a SUPPRESSED line — must NOT appear in output.
  p1.verbal_style.recurring_lines.push(
    { quote: "catch you later, cousins", where_used: "sign-off", medium: "spoken", pattern: null, position: "closing", delivery_note: "shouted", likely_habit: 0.5 });

  const p2 = base({});
  p2.pacing = { ...p2.pacing, total_length_seconds: 28, average_clip_length_seconds: 1.6 };
  p2.verbal_style = structuredClone(p2.verbal_style);
  p2.verbal_style.recurring_lines.push(
    { quote: "later, cousins", where_used: "sign-off", medium: "spoken", pattern: null, position: "closing", delivery_note: "shouted", likely_habit: 0.5 });

  return {
    profiles: [p0, p1, p2],
    suppressed: ["peace out, cousins"],   // the two "cousins" variants are paraphrases of this
    expect: {
      signoffEvidence: 3,                  // paraphrases count as the same sign-off
      divergentQuote: "worth the hype",    // evidence must be 1
      bannedSubstring: "cousins",          // suppressed — must be absent everywhere
    },
  };
}

// ---------------------------------------------------------------------------
function stripFences(s) {
  let t = s.trim();
  if (t.startsWith("```")) { const nl = t.indexOf("\n"); if (nl >= 0) t = t.slice(nl + 1); const c = t.lastIndexOf("```"); if (c >= 0) t = t.slice(0, c); }
  const a = t.indexOf("{"), b = t.lastIndexOf("}");
  if (a < 0 || b <= a) throw new Error("no JSON object");
  return t.slice(a, b + 1);
}
const norm = (s) => (s ?? "").toString().toLowerCase().replace(/\s+/g, " ").trim();

async function consolidationSchema() {
  // extraction schema + seen_in injected on lines / habits / beats (mirrors StyleConsolidator.schema).
  const s = JSON.parse(await readFile(join(here, "style-schema.json"), "utf8"));
  const seenIn = { type: "ARRAY", items: { type: "INTEGER" } };
  const line = s.properties.verbal_style.properties.recurring_lines.items;
  line.properties.seen_in = seenIn; line.propertyOrdering.push("seen_in"); line.required.push("seen_in");
  const habit = s.properties.habit_candidates.items;
  habit.properties.seen_in = seenIn; habit.propertyOrdering.push("seen_in"); habit.required.push("seen_in");
  const beat = s.properties.structure.properties.sections.items.properties.beats.items;
  beat.properties.seen_in = seenIn; beat.propertyOrdering.push("seen_in"); beat.required.push("seen_in");
  return s;
}

function checks(out, profiles, expect, suppressed) {
  const n = profiles.length;
  const vs = out.verbal_style ?? {};
  const lines = vs.recurring_lines ?? [];
  const habits = out.habit_candidates ?? [];
  const failures = [];

  const inRange = (arr) => Array.isArray(arr) && arr.every((i) => Number.isInteger(i) && i >= 0 && i < n);
  if (!lines.every((l) => inRange(l.seen_in))) failures.push("line seen_in missing/out-of-range");
  if (!habits.every((h) => inRange(h.seen_in))) failures.push("habit seen_in missing/out-of-range");

  // consistent sign-off (incl. paraphrases) — evidence must be N
  const signoffLine = lines.find((l) => norm(l.where_used) === "sign-off" && /next one/.test(norm(l.quote)));
  if (!signoffLine) failures.push("sign-off line missing");
  else if ((signoffLine.seen_in ?? []).length !== expect.signoffEvidence)
    failures.push(`sign-off evidence ${signoffLine.seen_in?.length} != ${expect.signoffEvidence}`);

  // divergent line — evidence must be exactly 1
  const divergent = lines.find((l) => norm(l.quote).includes(expect.divergentQuote) || norm(l.pattern).includes(expect.divergentQuote));
  if (divergent && (divergent.seen_in ?? []).length !== 1)
    failures.push(`divergent line evidence ${divergent.seen_in?.length} != 1`);

  // suppressed paraphrase — absent everywhere
  const allText = norm(JSON.stringify(vs));
  if (allText.includes(expect.bannedSubstring)) failures.push(`suppressed line resurfaced ("${expect.bannedSubstring}")`);

  // no duplicate normalized quotes
  const keys = lines.map((l) => norm(l.pattern || l.quote));
  if (new Set(keys).size !== keys.length) failures.push("duplicate normalized quotes");

  // numerics within min/max of inputs (the app overrides with exact averages; the model just can't be wild)
  for (const [path, get] of [
    ["total_length_seconds", (p) => p.pacing.total_length_seconds],
    ["average_clip_length_seconds", (p) => p.pacing.average_clip_length_seconds],
  ]) {
    const xs = profiles.map(get), v = get({ pacing: out.pacing ?? {} });
    if (!(v >= Math.min(...xs) - 1 && v <= Math.max(...xs) + 1)) failures.push(`${path} ${v} outside input range`);
  }

  // reveal honesty: some item has evidence < N → the script must NOT claim universal consistency for it,
  // and should carry a numeric-honesty phrase.
  const reveal = (out.reveal_script ?? []).join(" ");
  const anyPartial = lines.some((l) => (l.seen_in ?? []).length < n);
  if (anyPartial && !/\b(one|two|1|2) (of|out of)\b|\bin (one|two)\b|sometimes|not every/i.test(reveal) && /\balways\b|\bevery video\b/i.test(reveal))
    failures.push("reveal_script claims universal consistency despite partial evidence");

  return failures;
}

// ---------------------------------------------------------------------------
async function main() {
  await assertLockstep();
  const args = process.argv.slice(2);
  const synthetic = args.includes("--synthetic") || args.length === 0;

  let profiles, suppressed = [], expect = null;
  if (synthetic) {
    ({ profiles, suppressed, expect } = syntheticProfiles());
    console.log("▶ synthetic 3-source fixture (divergence + paraphrase-dedupe + suppression cases)");
  } else {
    profiles = await Promise.all(args.map(async (p) => JSON.parse(await readFile(p, "utf8"))));
    console.log(`▶ ${profiles.length} profiles from disk`);
  }

  const body = await readFile(join(here, "prompts/style-consolidate.txt"), "utf8");
  let prompt = body;
  if (suppressed.length)
    prompt += "\n\nREJECTED LINES — the creator said these are NOT their signature. Never output a recurring_line matching any of these, even paraphrased or partial:\n"
      + suppressed.map((s) => `- "${s}"`).join("\n");
  prompt += `\n\n=== SOURCE PROFILES (JSON array — source index = array position, 0-based, N = ${profiles.length}) ===\n${JSON.stringify(profiles)}`;

  const dir = join(here, "runs/style-consolidate", synthetic ? "synthetic" : "disk");
  await mkdir(dir, { recursive: true });
  const { text, httpMs } = await generate({ prompt, model: MODEL, schema: await consolidationSchema() });
  await writeFile(join(dir, "raw.json"), text);
  const out = JSON.parse(stripFences(text));
  await writeFile(join(dir, "consolidated.json"), JSON.stringify(out, null, 2));

  if (expect) {
    const failures = checks(out, profiles, expect, suppressed);
    await writeFile(join(dir, "checks.json"), JSON.stringify({ failures }, null, 2));
    if (failures.length) {
      console.log(`❌ ${failures.length} check(s) failed (${(httpMs / 1000).toFixed(1)}s):`);
      for (const f of failures) console.log(`   - ${f}`);
      process.exit(2);
    }
    console.log(`✅ all evidence-integrity checks passed (${(httpMs / 1000).toFixed(1)}s) → ${dir}/consolidated.json`);
  } else {
    console.log(`✅ consolidated (${(httpMs / 1000).toFixed(1)}s) → ${dir}/consolidated.json — inspect evidence counts + reveal_script by hand`);
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
