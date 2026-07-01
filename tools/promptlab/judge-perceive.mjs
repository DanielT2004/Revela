#!/usr/bin/env node
// Vela prompt lab — PERCEIVE accuracy judge. For each index.json (from run-perceive.mjs) it shows the judge
// model the proxy + the index + the transcript and grades how FAITHFULLY + COMPLETELY the index describes the
// footage — NOT editing quality (there are no editing decisions in a PERCEIVE index). Writes
// judge-perceive.json per run + runs/summary_perceive_judged.csv. accuracy_0_100 is RECOMPUTED in JS from the
// model's id-cited error list, so the number can't drift from the prose.
//
//   SUPABASE_PROJECT_REF=... SUPABASE_ANON_KEY=... node judge-perceive.mjs

import { readFile, writeFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { prepareVideo, generate } from "./lib/gemini.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);

const OPEN = "=== AUDIO TRANSCRIPT — GROUND TRUTH FOR TIMING ===";
const CLOSE = "=== END AUDIO TRANSCRIPT ===";
async function transcript(dir) {
  try { const f = await readFile(p(dir, "prompt.txt"), "utf8"); const a = f.indexOf(OPEN), b = f.indexOf(CLOSE); if (a >= 0 && b > a) return f.slice(a, b + CLOSE.length); } catch { /* none */ }
  return "(transcript unavailable — judge from the video's own audio)";
}

const DIMS = ["scene_type_accuracy", "depicts_accuracy", "references_accuracy", "reaction_accuracy", "segmentation_cleanliness", "coverage_completeness", "transcript_fidelity"];

const SCHEMA = {
  type: "OBJECT",
  properties: {
    dimensions: { type: "ARRAY", items: { type: "OBJECT", properties: { dimension: { type: "STRING", enum: DIMS }, score: { type: "INTEGER" }, justification: { type: "STRING" } }, propertyOrdering: ["dimension", "score", "justification"], required: ["dimension", "score", "justification"] } },
    per_shot_errors: { type: "ARRAY", items: { type: "OBJECT", properties: { shot_id: { type: "INTEGER" }, error_kind: { type: "STRING" }, detail: { type: "STRING" } }, propertyOrdering: ["shot_id", "error_kind", "detail"], required: ["shot_id", "error_kind", "detail"] } },
    missed_subjects: { type: "ARRAY", items: { type: "STRING" } },
    accuracy_0_100: { type: "INTEGER" },
    top_fix: { type: "STRING" },
  },
  propertyOrdering: ["dimensions", "per_shot_errors", "missed_subjects", "accuracy_0_100", "top_fix"],
  required: ["dimensions", "per_shot_errors", "missed_subjects", "accuracy_0_100", "top_fix"],
};

function judgePrompt(indexText, transcriptText, duration) {
  return `You are auditing a content INDEX of a food video for ACCURACY and COMPLETENESS — NOT editing quality. This index contains NO editing decisions (no keep/cut, order, hook, or b-roll); do not reward or punish editorial choices. Check ONLY whether the index faithfully and completely describes THIS footage.

The video is ${Math.round(duration)}s long. WATCH it, then compare it against the index below and the ground-truth transcript.

The index has "shots" (each: scene_type, description, depicts_subject = what the shot visually SHOWS, section = its narrative role, topic, hook_score, reaction_kind, has_speech) and "talk_spans" (each: spoken_text, references_subject = what the speech is ABOUT, is_to_camera).

Score each dimension 1 (badly wrong) to 5 (perfectly accurate). Every justification MUST cite specific shot ids.
- scene_type_accuracy: do the scene_type labels match what the camera shows?
- depicts_accuracy: does each non-empty depicts_subject actually appear on screen in that shot? Is anything obviously depictable left as ""?
- references_accuracy: does each talk_span's references_subject match what is being said (per spoken_text / transcript)?
- reaction_accuracy: are reaction_kind labels correct (a real first_taste / bite / verdict, not mislabeled chewing)?
- segmentation_cleanliness: do shot cuts fall on real subject / sentence boundaries (never mid-sentence), with no absurd merges or splits?
- coverage_completeness: list EVERY distinct DISH and PLACE you SEE in the video; for each, is there a shot whose depicts_subject or topic captures it? Put any subject the index MISSED into missed_subjects.
- transcript_fidelity: does spoken_text match the transcript verbatim, and is any spoken line missing from talk_spans?

Then return per_shot_errors (ONE entry per concrete, id-cited error you found across all dimensions), missed_subjects (dishes/places present in the video but absent from the index), accuracy_0_100 = max(0, 100 - 8*(number of per_shot_errors) - 15*(number of missed_subjects)), and the single most important top_fix.

Return ONLY the JSON.

=== INDEX ===
${indexText}

${transcriptText}`;
}

async function main() {
  const cfg = JSON.parse(await readFile(p("config-perceive.json"), "utf8"));
  if (cfg.judge?.enabled === false) { console.log("judge disabled in config-perceive.json"); return; }
  const model = cfg.judge?.model ?? "gemini-2.5-pro";
  const rows = [];
  const header = ["video", "run", ...DIMS, "errors", "missed", "accuracy", "top_fix"];

  for (const video of cfg.videos) {
    const dir = video.dir ?? `fixtures/${video.id}`;
    console.log(`\n⚖️  ${video.id} — uploading once for the judge…`);
    let file;
    try { file = await prepareVideo(p(dir, "proxy.mp4"), video.mimeType ?? "video/mp4"); }
    catch (e) { console.error(`   ✗ ${e.message}`); continue; }
    const tText = await transcript(dir);

    let cells = [];
    try { cells = (await readdir(p("runs", video.id))).filter((d) => d.startsWith("perceive__")).sort(); } catch { /* no runs */ }
    for (const cell of cells) {
      const rd = p("runs", video.id, cell);
      let indexText;
      try { indexText = await readFile(join(rd, "index.json"), "utf8"); }
      catch { console.log(`   • ${cell} … (no index.json, skipped)`); continue; }
      const runNo = (cell.match(/run(\d+)/) || [])[1] ?? "";
      process.stdout.write(`   • ${cell} … `);
      try {
        const res = await generate({ fileUri: file.uri, fileName: file.name, mimeType: file.mimeType, model, prompt: judgePrompt(indexText, tText, video.durationSeconds ?? 0), schema: SCHEMA, genConfig: { temperature: 0 } });
        const j = JSON.parse(res.text);
        const errs = (j.per_shot_errors || []).length, missed = (j.missed_subjects || []).length;
        const accuracy = Math.max(0, 100 - 8 * errs - 15 * missed); // recomputed in JS — authoritative
        j.accuracy_computed = accuracy;
        await writeFile(join(rd, "judge-perceive.json"), JSON.stringify(j, null, 2));
        const byDim = Object.fromEntries((j.dimensions || []).map((d) => [d.dimension, d.score]));
        rows.push([video.id, runNo, ...DIMS.map((d) => byDim[d] ?? ""), errs, missed, accuracy, j.top_fix ?? ""]);
        console.log(`accuracy ${accuracy}/100 (${errs} errs · ${missed} missed)`);
      } catch (e) { console.log(`✗ ${e.message}`); }
    }
  }

  const csvCell = (s) => { const x = String(s ?? ""); return /[",\n]/.test(x) ? `"${x.replace(/"/g, '""')}"` : x; };
  const csv = [header, ...rows].map((r) => r.map(csvCell).join(",")).join("\n") + "\n";
  await writeFile(p("runs", "summary_perceive_judged.csv"), csv);
  console.log(`\n✅ Wrote runs/summary_perceive_judged.csv (${rows.length} judged). Open it next to runs/summary_perceive.csv.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
