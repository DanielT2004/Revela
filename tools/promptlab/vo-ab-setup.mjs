#!/usr/bin/env node
// Voiceover A/B setup — generates two DECIDE fixtures that are IDENTICAL except for the single
// `plansVoiceover` narration line (the exact string BriefPromptBuilder.swift appends when the
// creator toggles "I'll record a voiceover" ON). Both share the same cached PERCEIVE index, so the
// ONLY variable across the two arms is that one line. Run once, then `node run-decide.mjs`.
//
//   node vo-ab-setup.mjs
//
// Writes:
//   fixtures/howlins-vo-off/prompt.txt   (control  — no voiceover line)
//   fixtures/howlins-vo-on/prompt.txt    (treatment — voiceover line after the lean bullet)
//   config-vo-ab-smoke.json              (1 run per arm — wiring check)
//   config-vo-ab.json                    (5 runs per arm — the real A/B)

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);
const MARKER = "=== AUDIO TRANSCRIPT — GROUND TRUTH FOR TIMING ===";

// The EXACT line BriefPromptBuilder.swift adds (block(for:), the `if b.plansVoiceover` branch),
// inserted right after the "Voiceover vs. on camera" lean bullet — same position as in the app.
const VO_LINE =
  "- The creator will record a fresh narration voiceover over the finished edit inside the app (this is separate from — and does not change — the strict in-footage voiceover_candidate rules below). Cut for a video that reads well under narration: favor visually strong segments, and beautiful food/action/payoff shots are worth keeping even where their live audio is weak or silent; do not fight to preserve spoken filler. Genuinely strong spoken moments (real reactions, punchy claims, the verdict) still deserve keep:true — the narration will be mixed around them.";

const INDEX_PATH = "runs/howlins/perceive__gemini-2.5-flash__run1/index.json";
const DURATION = 237.9;

// Canonical base = the howlins fixture's style+brief (everything before the transcript marker).
const full = await readFile(p("fixtures/howlins/prompt.txt"), "utf8");
const cut = full.indexOf(MARKER);
if (cut < 0) throw new Error("marker not found in fixtures/howlins/prompt.txt");
const base = full.slice(0, cut).trim();

// Find the lean bullet and insert the VO line on the following line (matching BriefPromptBuilder order).
const lines = base.split("\n");
const leanIdx = lines.findIndex((l) => l.startsWith("- Voiceover vs. on camera:"));
if (leanIdx < 0) throw new Error("could not find the '- Voiceover vs. on camera:' bullet to anchor the VO line");

const offText = base;                                  // control: no VO line
const onLines = [...lines];
onLines.splice(leanIdx + 1, 0, VO_LINE);               // treatment: VO line right after the lean bullet
const onText = onLines.join("\n");

// A trailing marker so the harness's styleBrief() slice keeps the whole style+brief block. DECIDE is
// text-only and everything after the marker is ignored by run-decide.mjs, so no transcript is needed.
const tail = `\n\n${MARKER}\n(Transcript omitted — DECIDE is text-only; the harness slices before this marker. This fixture exists only to A/B the voiceover brief line against ${INDEX_PATH}.)\n`;

await mkdir(p("fixtures/howlins-vo-off"), { recursive: true });
await mkdir(p("fixtures/howlins-vo-on"), { recursive: true });
await writeFile(p("fixtures/howlins-vo-off/prompt.txt"), offText + tail);
await writeFile(p("fixtures/howlins-vo-on/prompt.txt"), onText + tail);

const videos = [
  { id: "howlins-vo-off", dir: "fixtures/howlins-vo-off", indexPath: INDEX_PATH, durationSeconds: DURATION },
  { id: "howlins-vo-on", dir: "fixtures/howlins-vo-on", indexPath: INDEX_PATH, durationSeconds: DURATION },
];
// NOTE: the app hardcodes "gemini-2.5-pro" for DECIDE, but Google RETIRED the whole gemini-2.5-*
// family (both 2.5-pro and 2.5-flash now 404). "gemini-pro-latest" is the current pro tier and the
// correct successor for DECIDE — the app's decideModel needs the same update.
const MODEL = "gemini-pro-latest";
await writeFile(p("config-vo-ab-smoke.json"), JSON.stringify({ models: [MODEL], runs: 1, videos, judge: { enabled: false } }, null, 2));
await writeFile(p("config-vo-ab.json"), JSON.stringify({ models: [MODEL], runs: 5, videos, judge: { enabled: false } }, null, 2));

// Confirm the two arms differ by EXACTLY the one line.
const offSet = new Set(offText.split("\n"));
const added = onText.split("\n").filter((l) => !offSet.has(l));
console.log("✅ Voiceover A/B fixtures written.");
console.log(`   control  (off): fixtures/howlins-vo-off/prompt.txt  — ${offText.length} chars, ${lines.length} style+brief lines`);
console.log(`   treatment (on): fixtures/howlins-vo-on/prompt.txt   — ${onText.length} chars, +1 line`);
console.log(`   delta = ${added.length} line(s) added:`);
for (const l of added) console.log(`     + ${l.slice(0, 90)}…`);
console.log(`\n   index: ${INDEX_PATH} · model: ${MODEL}`);
console.log("\nNext:  set -a; . ./.env; set +a");
console.log("Smoke: RUN_CONFIG=config-vo-ab-smoke.json node run-decide.mjs   (1+1 wiring check)");
console.log("Full:  RUN_CONFIG=config-vo-ab.json node run-decide.mjs         (5+5 the real A/B)");
console.log("Report: node vo-ab-report.mjs");
