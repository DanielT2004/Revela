#!/usr/bin/env node
// Vela prompt lab — replay saved proxies against prompt/model/schema variants, off-device, in seconds.
//
//   GEMINI_API_KEY=... node run.mjs          # runs every cell in config.json
//
// For each video it uploads the proxy ONCE and reuses the fileUri across all prompt/model/schema cells,
// so a variant sweep is fast and isolates the PROMPT (the proxy bytes are frozen). Each cell writes
// runs/<video>/<prompt>__<model>__schema<bool>/{raw.json,plan.json,validation.json,timing.json}, and a
// joined runs/summary.csv with the violation score. Then `node judge.mjs` adds the LLM-judge columns.

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { prepareVideo, generate } from "./lib/gemini.mjs";
import { parsePlan, validatePlan } from "./lib/validate.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);

/**
 * Load a prompt file, composing other files so prompts stay DRY. Two mechanisms:
 *   `@extends other.txt`  (first line) — prepend other.txt, then this file's remainder.
 *   `{{other.txt}}`       (anywhere)   — inline other.txt at that spot (keeps the real style+brief+body order).
 */
async function loadPrompt(file) {
  let raw = await readFile(p("prompts", file), "utf8");
  const ext = raw.match(/^@extends\s+(\S+)\s*\n/);
  if (ext) raw = (await loadPrompt(ext[1])).trimEnd() + "\n\n" + raw.slice(ext[0].length);
  const re = /\{\{\s*([\w./-]+)\s*\}\}/g;
  let out = "", last = 0, m;
  while ((m = re.exec(raw))) { out += raw.slice(last, m.index) + (await loadPrompt(m[1])); last = m.index + m[0].length; }
  return out + raw.slice(last);
}

const csvCell = (s) => {
  const v = String(s ?? "");
  return /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
};

async function main() {
  const cfg = JSON.parse(await readFile(p("config.json"), "utf8"));
  const schema = JSON.parse(await readFile(p("schema.json"), "utf8"));
  const rows = [];
  const header = ["video", "prompt", "model", "schema", "score", "violations", "topViolations", "segments", "kept", "rawChars", "looksComplete", "httpMs"];

  for (const video of cfg.videos) {
    console.log(`\n📼 ${video.id} — uploading ${video.path} once…`);
    let file;
    try {
      file = await prepareVideo(p(video.path), video.mimeType ?? "video/mp4");
      console.log(`   ACTIVE → ${file.uri}`);
    } catch (e) {
      console.error(`   ✗ upload/activate failed: ${e.message}`);
      continue;
    }

    for (const promptFile of cfg.prompts) {
      const prompt = await loadPrompt(promptFile);
      for (const model of cfg.models) {
        for (const schemaOn of cfg.schemaOn) {
          const label = `${promptFile.replace(/\.txt$/, "")}__${model}__schema${schemaOn}`;
          const outDir = p("runs", video.id, label);
          await mkdir(outDir, { recursive: true });
          process.stdout.write(`   • ${label} … `);
          try {
            const res = await generate({
              fileUri: file.uri, fileName: file.name, mimeType: file.mimeType, prompt, model,
              schema: schemaOn ? schema : null,
            });
            await writeFile(join(outDir, "raw.json"), res.text);
            await writeFile(join(outDir, "timing.json"), JSON.stringify({ httpMs: res.httpMs }, null, 2));

            let report, plan, parseErr = null;
            try { plan = parsePlan(res.text); report = validatePlan(plan, video.durationSeconds ?? 0); }
            catch (e) { parseErr = e.message; }

            if (plan) await writeFile(join(outDir, "plan.json"), JSON.stringify(plan, null, 2));
            if (report) await writeFile(join(outDir, "validation.json"), JSON.stringify(report, null, 2));

            const top = report ? topViolations(report.violations) : (parseErr ? "PARSE_FAIL" : "");
            rows.push([video.id, promptFile, model, schemaOn,
              report ? report.score.toFixed(2) : "", report ? report.violations.length : "",
              top, report ? report.segmentCount : "", report ? report.keptCount : "",
              res.text.length, res.text.trim().endsWith("}"), res.httpMs]);
            console.log(report ? `score ${report.score.toFixed(2)} (${report.violations.length} viol)` : `⚠️ ${parseErr}`);
          } catch (e) {
            await writeFile(join(outDir, "error.txt"), e.message);
            rows.push([video.id, promptFile, model, schemaOn, "", "", "ERROR", "", "", "", "", ""]);
            console.log(`✗ ${e.message}`);
          }
        }
      }
    }
  }

  const csv = [header, ...rows].map((r) => r.map(csvCell).join(",")).join("\n") + "\n";
  await writeFile(p("runs", "summary.csv"), csv);
  console.log(`\n✅ Wrote runs/summary.csv (${rows.length} cells). Next: node judge.mjs`);
}

function topViolations(violations) {
  const m = {};
  for (const v of violations) m[v.kind] = (m[v.kind] || 0) + 1;
  return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([k, n]) => `${k}×${n}`).join(" ");
}

main().catch((e) => { console.error(e); process.exit(1); });
