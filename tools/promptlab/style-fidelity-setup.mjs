// Fidelity-fixture generator — takes a REAL PERCEIVE index + a template.json and emits four run-decide
// fixtures (the full A/B grid):
//
//   <base>-sig-v1/   injected signature talk_spans + v1 style block   (does the OLD block find them?)
//   <base>-sig-v2/   injected signature talk_spans + v2 style block   (fidelity arm)
//   <base>-plain-v1/ UNMODIFIED index + v1 block                      (regression baseline)
//   <base>-plain-v2/ UNMODIFIED index + v2 block                      (regression arm + negative control:
//                                                                      the block lists signatures the
//                                                                      footage does NOT contain)
//
//   node style-fidelity-setup.mjs --index runs/howlins/…index.json --template template.json \
//       --duration 120 --base howlins
//
// Injection validity (review-hardened): each signature span is written INSIDE an existing talking-head
// shot's window, REPLACING the spans it displaces — never floating over a food-closeup (a physically
// impossible index would make DECIDE behavior unrepresentative). truth.json records the target shot ids
// so check-signatures.mjs is fully deterministic. Then run:
//
//   RUN_CONFIG=config-style-fidelity.json node run-decide.mjs
//   node check-signatures.mjs
//   JUDGE_CONFIG=config-style-fidelity.json node judge.mjs     # regression arm: plain-v1 vs plain-v2

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { buildBlock, swiftSha256 } from "./build-style-block.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const MARKER = "=== AUDIO TRANSCRIPT — GROUND TRUTH FOR TIMING ===";

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

/** Pick a talking-head shot with speech in the given fraction range of the video. */
function pickTalkingHead(index, fromFrac, toFrac, exclude = new Set()) {
  const dur = index.duration_seconds ?? Math.max(...index.shots.map((s) => s.end_seconds));
  return index.shots.find((s) =>
    s.scene_type === "talking-head" && s.has_speech && !exclude.has(s.id) &&
    s.start_seconds >= dur * fromFrac && s.end_seconds <= dur * toFrac + 1 &&
    (s.end_seconds - s.start_seconds) >= 2);
}

/** Replace the talk_spans overlapping `shot` with ONE span speaking `text` (verbatim), inside the shot. */
function injectLine(index, shot, text) {
  const s0 = shot.start_seconds, s1 = shot.end_seconds;
  index.talk_spans = index.talk_spans.filter((sp) => sp.end_seconds <= s0 + 0.05 || sp.start_seconds >= s1 - 0.05);
  const start = s0 + Math.min(0.4, (s1 - s0) * 0.2);
  const end = Math.min(s1 - 0.1, start + Math.max(1.2, Math.min(3, text.split(" ").length * 0.35)));
  index.talk_spans.push({
    start_seconds: +start.toFixed(2), end_seconds: +end.toFixed(2), spoken_text: text,
    references_subject: shot.depicts_subject ?? "", also_references: [], is_to_camera: true,
  });
  index.talk_spans.sort((a, b) => a.start_seconds - b.start_seconds);
  return { shotId: shot.id, start: +start.toFixed(2), end: +end.toFixed(2), text };
}

async function writeFixture(dir, index, block, truth) {
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "index.json"), JSON.stringify(index, null, 1));
  // run-decide.mjs slices everything BEFORE the transcript marker as style+brief — the trailing marker
  // line makes prompt.txt consumable unchanged (the vo-ab trick).
  await writeFile(join(dir, "prompt.txt"), `${block}\n${MARKER}\n`);
  await writeFile(join(dir, "truth.json"), JSON.stringify(truth, null, 2));
}

async function main() {
  const indexPath = arg("index"), templatePath = arg("template");
  const base = arg("base", "fidelity"), duration = Number(arg("duration", 0));
  if (!indexPath || !templatePath) {
    console.error("usage: node style-fidelity-setup.mjs --index <perceive-index.json> --template <template.json> --base <name> [--duration s]");
    process.exit(1);
  }
  const template = JSON.parse(await readFile(templatePath, "utf8"));
  const vs = template.profile?.verbal_style ?? {};
  const spokenLines = (vs.recurring_lines ?? []).filter((l) => (l.medium ?? "spoken") !== "text-overlay");
  const signoff = ((spokenLines.find((l) => l.where_used === "sign-off")?.quote ?? vs.signoff) ?? "").trim();
  const hookLine = (spokenLines.find((l) => l.where_used === "hook")?.quote ?? "").trim();
  const ratingText = vs.rating_format ? "that's a 8.5 out of 10 for me" : "";
  // A creator may legitimately have NO spoken sign-off (visual close) — any ONE injectable signature
  // (sign-off, hook line, or rating) is enough to run the eval; absent ones are simply skipped.
  if (!signoff && !hookLine && !ratingText) {
    console.error("template has no injectable signatures (no sign-off, hook line, or rating) — fill verbal_style first");
    process.exit(1);
  }

  const blockV1 = buildBlock(template, { v1: true });
  const blockV2 = buildBlock(template, { v1: false });
  const meta = { swiftSha256: await swiftSha256() };

  const original = JSON.parse(await readFile(indexPath, "utf8"));
  const montage = !!(template.profile?.hook?.montage?.is_montage
                     && template.profile?.hook?.montage?.source !== "other-creators");

  // --- injected arm ---------------------------------------------------------
  const injected = structuredClone(original);
  const used = new Set();
  const truth = { injected: {}, negative: false, montage, meta };

  if (signoff) {
    const signoffShot = pickTalkingHead(injected, 0.7, 1.0, used);
    if (!signoffShot) { console.error("no talking-head shot in the final third to carry the sign-off"); process.exit(1); }
    used.add(signoffShot.id);
    truth.injected.signoff = injectLine(injected, signoffShot, signoff);
  }

  if (ratingText) {
    const ratingShot = pickTalkingHead(injected, 0.55, 0.98, used);
    if (ratingShot) { used.add(ratingShot.id); truth.injected.rating = injectLine(injected, ratingShot, ratingText); }
  }
  if (hookLine) {
    const hookShot = pickTalkingHead(injected, 0, 0.35, used);
    if (hookShot) { used.add(hookShot.id); truth.injected.hook = injectLine(injected, hookShot, hookLine); }
  }

  await writeFixture(join(here, "fixtures", `${base}-sig-v1`), injected, blockV1, { ...truth, arm: "v1" });
  await writeFixture(join(here, "fixtures", `${base}-sig-v2`), injected, blockV2, { ...truth, arm: "v2" });

  // --- plain arms (regression + negative control) ---------------------------
  const negTruth = { injected: {}, negative: true, signatures: { signoff, hookLine, ratingText }, meta };
  await writeFixture(join(here, "fixtures", `${base}-plain-v1`), original, blockV1, { ...negTruth, arm: "v1" });
  await writeFixture(join(here, "fixtures", `${base}-plain-v2`), original, blockV2, { ...negTruth, arm: "v2" });

  const cfg = {
    _readme: "Generated by style-fidelity-setup.mjs. sig-* = injected-signature fidelity arms; plain-* = regression (judge plain-v1 vs plain-v2) + negative control (plain-v2 must not fabricate).",
    videos: [`${base}-sig-v1`, `${base}-sig-v2`, `${base}-plain-v1`, `${base}-plain-v2`].map((id) => ({
      id, dir: `fixtures/${id}`, indexPath: `fixtures/${id}/index.json`, durationSeconds: duration || (original.duration_seconds ?? 0),
    })),
    models: ["gemini-pro-latest"],
    runs: 5,
  };
  await writeFile(join(here, "config-style-fidelity.json"), JSON.stringify(cfg, null, 2));
  console.log(`✅ 4 fixtures under fixtures/${base}-* and config-style-fidelity.json written.`);
  const injectedBits = Object.entries(truth.injected).map(([k, v]) => `${k}→shot ${v.shotId}`);
  console.log(`   injected: ${injectedBits.length ? injectedBits.join(", ") : "(none)"}${montage ? " · montage template" : ""}`);
  console.log("   next: RUN_CONFIG=config-style-fidelity.json node run-decide.mjs && node check-signatures.mjs");
}

main().catch((e) => { console.error(e); process.exit(1); });
