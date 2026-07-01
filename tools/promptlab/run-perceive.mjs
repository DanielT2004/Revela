#!/usr/bin/env node
// Vela prompt lab — PERCEIVE runner. Runs the describe-only "content index" prompt (perceive.txt) against a
// saved proxy, off-device, through the same Supabase proxy the app uses. PERCEIVE makes ZERO editing
// decisions — it emits {duration_seconds, video_summary, shots[], talk_spans[]} — so it has its OWN schema
// (perceive-schema.json) and validator (validate-perceive.mjs), separate from the edit-plan run.mjs.
//
//   SUPABASE_PROJECT_REF=... SUPABASE_ANON_KEY=... node run-perceive.mjs
//
// For each video it PREPENDS the transcript block (sliced from the saved bundle's prompt.txt, falling back to
// a duration-only block) so PERCEIVE has the same ground-truth timing the app gives Gemini. Thinking is on
// via genConfig (no lib change). Writes runs/<video>/perceive__<model>__run<i>/{raw,index,validation,timing}.json
// + runs/summary_perceive.csv. Then `node judge-perceive.mjs` adds the accuracy columns.

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { prepareVideo, generate } from "./lib/gemini.mjs";
import { parseIndex, validateIndex } from "./validate-perceive.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);

const OPEN = "=== AUDIO TRANSCRIPT — GROUND TRUTH FOR TIMING ===";
const CLOSE = "=== END AUDIO TRANSCRIPT ===";

/** Slice the transcript block from a saved bundle's prompt.txt; fall back to a duration-only block. */
async function transcriptBlock(dir, durationSeconds) {
  try {
    const full = await readFile(p(dir, "prompt.txt"), "utf8");
    const a = full.indexOf(OPEN), b = full.indexOf(CLOSE);
    if (a >= 0 && b > a) return full.slice(a, b + CLOSE.length);
  } catch { /* no bundle prompt.txt — fall through */ }
  const dur = Number(durationSeconds).toFixed(1);
  return `${OPEN}\n\nThis video is EXACTLY ${dur} seconds long. Every timestamp you output must lie between 0 and ${dur} seconds.\n(No separate transcript was available — listen to the video's own audio to time and transcribe the speech.)\n\n${CLOSE}`;
}

const csvCell = (s) => { const x = String(s ?? ""); return /[",\n]/.test(x) ? `"${x.replace(/"/g, '""')}"` : x; };
const topViolations = (vs) => {
  const m = {}; for (const x of vs) m[x.kind] = (m[x.kind] || 0) + 1;
  return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k, n]) => `${k}×${n}`).join(" ");
};

async function main() {
  const cfg = JSON.parse(await readFile(p("config-perceive.json"), "utf8"));
  const perceive = await readFile(p("prompts", process.env.PROMPT_FILE || "perceive.txt"), "utf8");
  const schema = JSON.parse(await readFile(p("perceive-schema.json"), "utf8"));
  const model = cfg.model ?? "gemini-2.5-flash";
  const N = cfg.runs ?? 1;
  const genConfig = cfg.thinkingBudget ? { thinkingConfig: { thinkingBudget: cfg.thinkingBudget } } : {};
  const rows = [];
  const header = ["video", "run", "score", "violations", "topViolations", "shots", "spans", "depicts", "toCameraSpans", "rawChars", "looksComplete", "httpMs"];

  for (const video of cfg.videos) {
    const dir = video.dir ?? `fixtures/${video.id}`;
    console.log(`\n📼 ${video.id} — uploading ${dir}/proxy.mp4 once…`);
    let file;
    try { file = await prepareVideo(p(dir, "proxy.mp4"), video.mimeType ?? "video/mp4"); console.log(`   ACTIVE → ${file.uri}`); }
    catch (e) { console.error(`   ✗ upload failed: ${e.message}`); continue; }

    let truth = null;
    try { truth = JSON.parse(await readFile(p("fixtures", `${video.id}.truth.json`), "utf8")); console.log(`   (using fixtures/${video.id}.truth.json for completeness)`); } catch { /* optional */ }

    const prompt = `${await transcriptBlock(dir, video.durationSeconds ?? 0)}\n\n${perceive}`;

    for (let i = 1; i <= N; i++) {
      const label = `perceive__${model}__run${i}`;
      const outDir = p("runs", video.id, label);
      await mkdir(outDir, { recursive: true });
      process.stdout.write(`   • ${label} … `);
      try {
        const res = await generate({ fileUri: file.uri, fileName: file.name, mimeType: file.mimeType, prompt, model, schema, genConfig });
        await writeFile(join(outDir, "raw.json"), res.text);
        await writeFile(join(outDir, "timing.json"), JSON.stringify({ httpMs: res.httpMs }, null, 2));

        let report, index, parseErr = null;
        try { index = parseIndex(res.text); report = validateIndex(index, video.durationSeconds ?? 0, truth); }
        catch (e) { parseErr = e.message; }
        if (index) await writeFile(join(outDir, "index.json"), JSON.stringify(index, null, 2));
        if (report) await writeFile(join(outDir, "validation.json"), JSON.stringify(report, null, 2));

        rows.push([video.id, i,
          report ? report.score.toFixed(2) : "", report ? report.violations.length : "",
          report ? topViolations(report.violations) : (parseErr ? "PARSE_FAIL" : ""),
          report ? report.shotCount : "", report ? report.spanCount : "",
          report ? report.depictsCount : "", report ? report.toCameraSpans : "",
          res.text.length, res.text.trim().endsWith("}"), res.httpMs]);
        console.log(report ? `score ${report.score.toFixed(2)} (${report.violations.length} viol · ${report.shotCount} shots · ${report.spanCount} spans · ${report.depictsCount} depict)` : `⚠️ ${parseErr}`);
      } catch (e) {
        await writeFile(join(outDir, "error.txt"), e.message);
        rows.push([video.id, i, "", "", "ERROR", "", "", "", "", "", "", ""]);
        console.log(`✗ ${e.message}`);
      }
    }
  }

  const csv = [header, ...rows].map((r) => r.map(csvCell).join(",")).join("\n") + "\n";
  await writeFile(p("runs", "summary_perceive.csv"), csv);
  console.log(`\n✅ Wrote runs/summary_perceive.csv (${rows.length} run(s)). Next: node judge-perceive.mjs`);
}

main().catch((e) => { console.error(e); process.exit(1); });
