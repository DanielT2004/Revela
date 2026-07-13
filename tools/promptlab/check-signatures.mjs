// Deterministic signature-fidelity checker — NO LLM. Walks runs/<fixture>/decide__*__run*/decisions.json
// for every fixture in config-style-fidelity.json and asserts the M3 placement contract against each
// fixture's truth.json (written by style-fidelity-setup.mjs):
//
//   injected fixtures (sig-*):
//     kept        — the sign-off/rating/hook shots appear in final_edit_order
//     signoff_last— the sign-off shot IS the last element of final_edit_order
//     rating_end  — the rating shot is within the last two of final_edit_order (before the sign-off)
//     hook_top    — the hook-line shot is final_edit_order[0] or inside cold_open
//     no_cut_thru — no trims[] entry stops inside an injected span (never trim through a signature)
//     notes       — style_match_notes mentions the found signatures
//   negative fixtures (plain-*):
//     no_fabrication — style_match_notes must not claim a signature was FOUND/PLACED (hard 0-tolerance)
//
// Pass bars (per arm, over N runs): kept/signoff_last/rating_end/hook_top ≥ 4/5 · no_cut_thru 5/5 ·
// notes 5/5 · fabrications 0/5. Compare v1 vs v2 columns in runs/summary_signatures.csv.
//
// Also enforces the mirror-drift guard: if a fixture's truth.json carries meta.swiftSha256, the CURRENT
// StyleConstraintBuilder.swift hash must match — else the fixtures were built from an outdated mirror.

import { readFile, writeFile, readdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { swiftSha256 } from "./build-style-block.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const norm = (s) => (s ?? "").toString().toLowerCase();

async function main() {
  const cfg = JSON.parse(await readFile(join(here, process.env.CONFIG ?? "config-style-fidelity.json"), "utf8"));
  const currentSha = await swiftSha256();
  const rows = [];

  for (const video of cfg.videos) {
    const truth = JSON.parse(await readFile(join(here, video.dir, "truth.json"), "utf8"));
    if (truth.meta?.swiftSha256 && truth.meta.swiftSha256 !== currentSha) {
      console.error(`❌ MIRROR OUT OF DATE: fixtures for ${video.id} were built from an older StyleConstraintBuilder.swift — re-run style-fidelity-setup.mjs.`);
      process.exit(3);
    }

    let cells = [];
    try { cells = (await readdir(join(here, "runs", video.id))).filter((d) => d.startsWith("decide__")); }
    catch { console.log(`(no runs for ${video.id} yet)`); continue; }

    for (const cell of cells) {
      const dir = join(here, "runs", video.id, cell);
      let d;
      try { d = JSON.parse(await readFile(join(dir, "decisions.json"), "utf8")); }
      catch { rows.push({ fixture: video.id, cell, parse: false }); continue; }

      const order = d.final_edit_order ?? [];
      const cold = d.cold_open ?? [];
      const trims = d.trims ?? [];
      const notes = norm(d.style_match_notes);
      const r = { fixture: video.id, cell, parse: true };

      if (!truth.negative) {
        const inj = truth.injected;
        // Own-footage teaser-montage opener (set by style-fidelity-setup when the template carries it):
        // the cold open must be a 2-3 shot teaser whose KEPT durations are actually short. Durations come
        // from the fixture's index (shot end − start, or the trim when one is set) — a real assertion,
        // not a formality.
        if (truth.montage) {
          // The TEASER is the run of short VISUAL (non-talking) shots at the FRONT of the cold open —
          // the cold open legitimately continues with the spoken intro line + a tease after it, so
          // never measure cold_open's total length (a 2-shot hook+context would pass vacuously and a
          // correct teaser+intro+tease would fail).
          try {
            const idx = JSON.parse(await readFile(join(here, video.dir, "index.json"), "utf8"));
            const shotById = Object.fromEntries((idx.shots ?? []).map((s) => [s.id, s]));
            const keptDur = (id) => {
              const s = shotById[id]; if (!s) return Infinity;
              const t = trims.find((x) => x.shot_id === id);
              return (t ? t.trim_to_seconds : s.end_seconds) - s.start_seconds;
            };
            let teaser = [];
            for (const id of cold) {
              if ((shotById[id]?.scene_type ?? "talking-head") === "talking-head") break;
              teaser.push(id);
              if (teaser.length >= 4) break;
            }
            r.montage_cold_open = teaser.length >= 2 && teaser.length <= 3;
            r.montage_short_cuts = teaser.length >= 2 && teaser.every((id) => keptDur(id) <= 2.0);
          } catch { r.montage_cold_open = false; r.montage_short_cuts = false; }
        }
        if (inj.signoff) {
          r.signoff_kept = order.includes(inj.signoff.shotId);
          r.signoff_last = order.length > 0 && order[order.length - 1] === inj.signoff.shotId;
          r.signoff_noted = notes.includes("sign") || notes.includes(norm(inj.signoff.text).slice(0, 18));
        }
        if (inj.rating) {
          r.rating_kept = order.includes(inj.rating.shotId);
          r.rating_end = order.slice(-2).includes(inj.rating.shotId);
          r.rating_not_cold_open = !cold.includes(inj.rating.shotId);
        }
        if (inj.hook) {
          r.hook_kept = order.includes(inj.hook.shotId);
          r.hook_top = order[0] === inj.hook.shotId || cold.includes(inj.hook.shotId);
        }
        // never trim THROUGH an injected span (a trim may end after the span; not inside it)
        r.no_cut_through = Object.values(inj).every((sig) =>
          trims.every((t) => t.shot_id !== sig.shotId || t.trim_to_seconds >= sig.end - 0.05));
      } else {
        // negative control — the block lists signatures the footage does NOT contain; claiming one was
        // found/placed is a fabrication (a "not found / footage didn't contain" mention is correct).
        const claims = /(sign-?off|signature|rating).{0,50}\b(found|placed|kept|ends the video|closes the video|as the final)\b/i.test(d.style_match_notes ?? "");
        const negates = /\b(no|not|didn't|does ?n[o']t|couldn'?t|missing|absent|wasn'?t)\b/i.test(d.style_match_notes ?? "");
        r.no_fabrication = !claims || negates;
      }
      rows.push(r);
    }
  }

  const cols = ["fixture", "cell", "parse", "signoff_kept", "signoff_last", "signoff_noted",
    "rating_kept", "rating_end", "rating_not_cold_open", "hook_kept", "hook_top",
    "montage_cold_open", "montage_short_cuts", "no_cut_through", "no_fabrication"];
  const csv = [cols.join(","), ...rows.map((r) => cols.map((c) => JSON.stringify(r[c] ?? "")).join(","))].join("\n");
  await writeFile(join(here, "runs/summary_signatures.csv"), csv);

  // per-fixture rate summary to the console
  const byFixture = {};
  for (const r of rows) (byFixture[r.fixture] ??= []).push(r);
  let hardFail = false;
  for (const [fx, rs] of Object.entries(byFixture)) {
    const rate = (k) => { const xs = rs.filter((r) => r[k] !== undefined); return xs.length ? `${xs.filter((r) => r[k]).length}/${xs.length}` : "—"; };
    const fabs = rs.filter((r) => r.no_fabrication === false).length;
    if (fabs > 0) hardFail = true;
    console.log(`${fx}: parse ${rate("parse")} · signoff kept ${rate("signoff_kept")} last ${rate("signoff_last")} noted ${rate("signoff_noted")} · rating end ${rate("rating_end")} · hook top ${rate("hook_top")} · no-cut-through ${rate("no_cut_through")} · no-fabrication ${rate("no_fabrication")}`);
  }
  console.log(`\n✅ runs/summary_signatures.csv (${rows.length} cells). Pass bars: signoff_last/rating_end/hook_top ≥ 4/5 on the v2 arm · no_cut_through all · fabrications 0 (HARD).`);
  if (hardFail) { console.error("❌ HARD FAIL: fabrication detected on a negative-control fixture."); process.exit(2); }
}

main().catch((e) => { console.error(e); process.exit(1); });
