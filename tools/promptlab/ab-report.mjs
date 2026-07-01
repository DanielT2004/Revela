#!/usr/bin/env node
// A/B reporter — for each decide__<cell>__run<i> dir, print the objective metrics (validation score,
// duration, kept count) + the resolved storyboard, so a human/AI judge can read all cells head-to-head.
//   node ab-report.mjs [cellPrefix=decide__sonnet-]
import { readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveCut } from "./resolve-cut.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...x) => join(HERE, ...x);
const prefix = process.argv[2] || "decide__sonnet-";
const VIDEO = "howlins";

const index = JSON.parse(await readFile(p("runs", VIDEO, "perceive__gemini-2.5-flash__run1/index.json"), "utf8").catch(() =>
  readFile(p("runs/howlins/perceive__gemini-2.5-flash__run1/index.json"), "utf8")));

const dirs = (await readdir(p("runs", VIDEO))).filter((d) => d.startsWith(prefix)).sort();
for (const cell of dirs) {
  const dir = p("runs", VIDEO, cell);
  let plan, val, timing;
  try { plan = JSON.parse(await readFile(join(dir, "plan.json"), "utf8")); }
  catch { console.log(`\n########## ${cell} — NO plan.json (failed) ##########\n`); continue; }
  try { val = JSON.parse(await readFile(join(dir, "validation.json"), "utf8")); } catch {}
  try { timing = JSON.parse(await readFile(join(dir, "timing.json"), "utf8")); } catch {}
  const { storyboard, totalDuration } = resolveCut(plan, index);
  console.log(`\n########## ${cell} ##########`);
  console.log(`objective: validation ${val ? val.score.toFixed(2) : "?"} · ${val ? val.violations.length : "?"} violations · kept ${plan.final_edit_order.length} · broll ${plan.broll_placements.length} · resolved ${totalDuration.toFixed(1)}s vs target ${plan.recommended_duration}s · gen ${timing ? (timing.httpMs / 1000).toFixed(0) + "s" : "?"}`);
  if (val?.violations?.length) console.log(`violations: ${val.violations.map((v) => `${v.kind}(${v.segmentId ?? "-"})`).join(", ")}`);
  console.log(storyboard);
}
