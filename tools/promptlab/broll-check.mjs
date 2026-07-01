#!/usr/bin/env node
// B-ROLL PLACEMENT AUDIT — for each overlay, map its exact time window to the WORDS spoken underneath it
// (in source time) and the VISUAL it shows, so we can judge whether the placement is logical (overlay
// depicts what's being said at that moment). Answers "is the b-roll in the RIGHT place?"
//   node broll-check.mjs decide__sonnet-8k
import { readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);
const prefix = process.argv[2] || "decide__sonnet-8k";
const index = JSON.parse(await readFile(p("runs/howlins/perceive__gemini-2.5-flash__run1/index.json"), "utf8"));
const shot = (id) => (index.shots ?? []).find((s) => s.id === id) ?? {};
const spokenOver = (a, b) => (index.talk_spans ?? [])
  .filter((sp) => sp.start_seconds < b - 0.05 && sp.end_seconds > a + 0.05)
  .map((sp) => (sp.spoken_text ?? "").trim()).filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
const refsOver = (a, b) => [...new Set((index.talk_spans ?? [])
  .filter((sp) => sp.start_seconds < b - 0.05 && sp.end_seconds > a + 0.05)
  .map((sp) => sp.references_subject).filter(Boolean))].join(", ");

const dirs = (await readdir(p("runs", "howlins"))).filter((d) => d.startsWith(prefix)).sort();
for (const cell of dirs) {
  let plan;
  try { plan = JSON.parse(await readFile(p("runs", "howlins", cell, "plan.json"), "utf8")); } catch { continue; }
  console.log(`\n===== ${cell} — ${plan.broll_placements.length} b-roll placement(s) =====`);
  for (const b of plan.broll_placements) {
    const over = shot(b.over_segment_id), src = shot(b.broll_segment_id);
    const a = (over.start_seconds ?? 0) + (b.start_offset_seconds ?? 0);
    const z = a + (b.duration_seconds ?? 0);
    console.log(`\n• overlay ${b.duration_seconds}s at source [${a.toFixed(1)}–${z.toFixed(1)}s], over shot ${b.over_segment_id}:`);
    console.log(`   WORDS SPOKEN under it: "${spokenOver(a, z) || "(silence)"}"  [talk refers to: ${refsOver(a, z) || "—"}]`);
    console.log(`   B-ROLL SHOWS shot ${b.broll_segment_id}: "${src.description ?? "?"}"  [depicts: ${src.depicts_subject ?? "?"}]`);
    console.log(`   model's reason: ${b.reason ?? "—"}`);
  }
}
