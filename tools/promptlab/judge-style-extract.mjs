// LLM judge for style-extraction runs — grades each profile.json produced by run-style-extract.mjs on the
// subjective dimensions the deterministic checks can't measure. Mirrors judge.mjs conventions (text-only
// generate through the proxy, one judge call per cell, medians across runs are computed by the reader).
//
//   node judge-style-extract.mjs                        # walks runs/style/** → runs/summary_style_judged.csv
//
// Rubric (each 1–5 + a one-line justification citing evidence):
//   verbal_identity_capture — did it find the catchphrases/sign-off/rating formula that exist (per truth)?
//   quote_verbatimness      — are quotes word-for-word plausible transcriptions vs paraphrases?
//   beat_generalization     — are section beats format-level labels (menu specifics only in "example")?
//   habit_specificity       — do habit_candidates describe THIS creator (penalize generic-six lookalikes
//                             like "jump cuts over silence" / "cut on the beat" with no creator specifics)?
//   reveal_script_quality   — second person, specific, quotes their words, honest for one video (no
//                             "always"/"every video"), warm but not sycophantic?
//   overall_capture         — 0–100: would a stranger reading ONLY this profile recreate THIS creator?

import { readFile, writeFile, readdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { generate } from "./lib/gemini.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const JUDGE_MODEL = process.env.JUDGE_MODEL ?? "gemini-pro-latest";

function judgePrompt(profileJSON, truthJSON) {
  return `You are grading how well an AI reverse-engineered a food creator's editing style from ONE finished TikTok.
You are given the PROFILE it produced and a TRUTH file written by a human who knows the creator (ground truth
for what signatures actually exist). Grade the PROFILE, not the creator.

Return ONLY a JSON object:
{
  "verbal_identity_capture": 1-5, "verbal_identity_capture_why": "...",
  "quote_verbatimness": 1-5, "quote_verbatimness_why": "...",
  "beat_generalization": 1-5, "beat_generalization_why": "...",
  "habit_specificity": 1-5, "habit_specificity_why": "...",
  "reveal_script_quality": 1-5, "reveal_script_quality_why": "...",
  "overall_capture": 0-100,
  "top_miss": "the single most important thing the profile failed to capture, or null"
}

Grading notes:
- verbal_identity_capture: the TRUTH lists real catchphrases / sign-off / rating format. 5 = all present in
  verbal_style with correct roles; 1 = none.
- quote_verbatimness: quotes must read like transcriptions, not summaries ("let's see if it's worth the
  hype" not "asks if it's worth trying"). Templated lines should carry a pattern with a placeholder.
- beat_generalization: 5 = every beat label reusable on ANY future video in this format, specifics demoted
  to "example"; 1 = labels name this video's dishes/places.
- habit_specificity: 5 = habits are recognizably THIS creator, correctly kind-classified; dock points for
  generic filler that could describe any food account.
- reveal_script_quality: it must be second person, quote their own words at least once, never claim
  "always"/"every video" from a single video, and feel like a sharp friend — not a horoscope.

=== TRUTH ===
${truthJSON}

=== PROFILE ===
${profileJSON}`;
}

function stripFences(s) {
  let t = s.trim();
  if (t.startsWith("```")) { const nl = t.indexOf("\n"); if (nl >= 0) t = t.slice(nl + 1); const c = t.lastIndexOf("```"); if (c >= 0) t = t.slice(0, c); }
  const a = t.indexOf("{"), b = t.lastIndexOf("}");
  return t.slice(a, b + 1);
}

async function main() {
  const root = join(here, "runs/style");
  const cfg = JSON.parse(await readFile(join(here, process.env.CONFIG ?? "config-style-extract.json"), "utf8"));
  const truthById = Object.fromEntries(await Promise.all(
    cfg.fixtures.map(async (f) => [f.id, await readFile(join(here, f.truth), "utf8")])
  ));

  const rows = [];
  for (const fixture of await readdir(root)) {
    const truth = truthById[fixture];
    if (!truth) { console.log(`(skip ${fixture} — not in config)`); continue; }
    for (const cell of await readdir(join(root, fixture))) {
      const dir = join(root, fixture, cell);
      let profile;
      try { profile = await readFile(join(dir, "profile.json"), "utf8"); }
      catch { rows.push({ fixture, cell, error: "no profile.json (parse fail)" }); continue; }
      process.stdout.write(`⚖️  ${fixture} · ${cell} … `);
      try {
        const { text } = await generate({ prompt: judgePrompt(profile, truth), model: JUDGE_MODEL });
        const j = JSON.parse(stripFences(text));
        await writeFile(join(dir, "judge.json"), JSON.stringify(j, null, 2));
        rows.push({ fixture, cell, ...j });
        console.log(`overall ${j.overall_capture}`);
      } catch (e) {
        rows.push({ fixture, cell, error: String(e).slice(0, 120) });
        console.log(`ERROR: ${e}`);
      }
    }
  }

  const cols = ["fixture", "cell", "verbal_identity_capture", "quote_verbatimness", "beat_generalization",
    "habit_specificity", "reveal_script_quality", "overall_capture", "top_miss", "error"];
  const csv = [cols.join(","), ...rows.map((r) => cols.map((c) => JSON.stringify(r[c] ?? "")).join(","))].join("\n");
  await writeFile(join(here, "runs/summary_style_judged.csv"), csv);
  console.log(`\n✅ ${rows.length} judged → runs/summary_style_judged.csv`);
}

main().catch((e) => { console.error(e); process.exit(1); });
