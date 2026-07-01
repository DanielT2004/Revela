// Structural validator for a PERCEIVE content index — the deterministic first gate before the accuracy judge.
// Mirrors lib/validate.mjs's shape (parse + severity/penalty + TOL coverage), but for the {shots, talk_spans}
// content-index schema, NOT the edit plan. Objective ONLY: internal consistency + coverage geometry +
// completeness floors. No taste. An index that fails here isn't worth judging.

const TOL = 0.25; // seconds of slop before a gap/overlap/over-length counts (model timestamps are coarse)
const SCENE_TYPES = ["food-closeup", "talking-head", "bite-reaction", "plating", "ambiance", "wide-shot", "transition"];
const SECTIONS = ["intro", "middle", "end"];
const REACTIONS = ["none", "bite", "first_taste", "verdict", "peak_reaction"];
const QFLAGS = ["dead_air", "duplicate_take", "false_start", "camera_adjust", "audio_issue"];

/** Strip ```fences``` and grab the outermost {...}, mirroring lib/validate.mjs parsePlan. */
export function parseIndex(rawText) {
  let s = String(rawText).trim();
  if (s.startsWith("```")) {
    const nl = s.indexOf("\n"); if (nl >= 0) s = s.slice(nl + 1);
    const c = s.lastIndexOf("```"); if (c >= 0) s = s.slice(0, c);
    s = s.trim();
  }
  const a = s.indexOf("{"), b = s.lastIndexOf("}");
  if (a < 0 || b < 0 || a >= b) throw new Error("no JSON object in model text");
  return JSON.parse(s.slice(a, b + 1));
}

const fmt = (d) => Number(d).toFixed(2);
const words = (s) => String(s).trim().split(/\s+/).filter(Boolean);

/**
 * Validate a PERCEIVE index. `truth` (optional, hand-authored fixtures/<id>.truth.json) turns completeness
 * into a hard check for the fixture we iterate on.
 * @returns {{score, violations, summary, shotCount, spanCount, depictsCount, toCameraSpans, proxyDuration}}
 */
export function validateIndex(index, proxyDuration = 0, truth = null) {
  const v = [];
  const shots = Array.isArray(index.shots) ? index.shots : [];
  const spans = Array.isArray(index.talk_spans) ? index.talk_spans : [];
  const add = (kind, severity, detail, id = null) => v.push({ kind, severity, detail, shotId: id });
  const dur = proxyDuration > 0 ? proxyDuration : (Number(index.duration_seconds) || 0);

  if (proxyDuration > 0 && index.duration_seconds != null && Math.abs(index.duration_seconds - proxyDuration) > 1)
    add("durationMismatch", "medium", `index duration_seconds ${fmt(index.duration_seconds)} differs from the proxy's ${fmt(proxyDuration)}s`);

  // per-shot shape + field legality
  for (const s of shots) {
    const len = s.end_seconds - s.start_seconds;
    if (len > 15 + TOL) add("shotTooLong", "high", `shot ${s.id} is ${fmt(len)}s (> 15s cap)`, s.id);
    if (s.end_seconds <= s.start_seconds) add("nonPositiveDuration", "high", `shot ${s.id} end ≤ start`, s.id);
    if (s.start_seconds < -TOL) add("startBeforeZero", "high", `shot ${s.id} starts at ${fmt(s.start_seconds)}`, s.id);
    if (dur > 0 && s.end_seconds > dur + TOL) add("endBeyondVideo", "high", `shot ${s.id} ends at ${fmt(s.end_seconds)} but the video is ${fmt(dur)}s`, s.id);
    if (!SCENE_TYPES.includes(s.scene_type)) add("badSceneType", "low", `shot ${s.id} bad scene_type "${s.scene_type}"`, s.id);
    if (!SECTIONS.includes(s.section)) add("badSection", "low", `shot ${s.id} bad section "${s.section}"`, s.id);
    if (!REACTIONS.includes(s.reaction_kind)) add("badReactionKind", "low", `shot ${s.id} bad reaction_kind "${s.reaction_kind}"`, s.id);
    if (Array.isArray(s.quality_flags)) { for (const f of s.quality_flags) if (!QFLAGS.includes(f)) add("badQualityFlag", "low", `shot ${s.id} bad quality_flag "${f}"`, s.id); }
    else add("badQualityFlag", "low", `shot ${s.id} quality_flags is not an array`, s.id);
    if (!(Number.isInteger(s.hook_score) && s.hook_score >= 0 && s.hook_score <= 10)) add("hookScoreOutOfRange", "low", `shot ${s.id} hook_score ${s.hook_score}`, s.id);
    if (!(s.confidence >= 0 && s.confidence <= 1)) add("confidenceOutOfRange", "low", `shot ${s.id} confidence ${s.confidence}`, s.id);
    if (typeof s.depicts_subject === "string" && s.depicts_subject !== "" && words(s.depicts_subject).length > 3)
      add("depictsSubjectFormat", "low", `shot ${s.id} depicts_subject "${s.depicts_subject}" is > 3 words`, s.id);
  }

  // ids unique + ascending by start
  const ids = shots.map((s) => s.id);
  if (new Set(ids).size !== ids.length) add("duplicateId", "high", "shot ids are not unique");
  for (let i = 1; i < shots.length; i++)
    if (shots[i].start_seconds < shots[i - 1].start_seconds - TOL) { add("idsNotAscending", "low", `shots not ordered by start_seconds at id ${shots[i].id}`, shots[i].id); break; }

  // coverage tiling [0, dur] (the after-last gap doubles as a truncation detector)
  const ordered = [...shots].sort((a, b) => a.start_seconds - b.start_seconds);
  if (ordered.length) {
    if (ordered[0].start_seconds > TOL) add("coverageGap", "medium", `${fmt(ordered[0].start_seconds)}s hole before the first shot`, ordered[0].id);
    let prevEnd = ordered[0].start_seconds;
    for (const s of ordered) {
      const gap = s.start_seconds - prevEnd;
      if (gap > TOL) add("coverageGap", "medium", `${fmt(gap)}s gap before shot ${s.id}`, s.id);
      else if (gap < -TOL) add("coverageOverlap", "medium", `shot ${s.id} overlaps the previous by ${fmt(-gap)}s`, s.id);
      prevEnd = Math.max(prevEnd, s.end_seconds);
    }
    if (dur > 0 && dur - prevEnd > TOL) add("coverageGap", "medium", `${fmt(dur - prevEnd)}s of video after the last shot is uncovered (possible truncation)`);
  } else add("noShots", "high", "index has no shots");

  // talk_spans
  let toCamera = 0;
  for (const sp of spans) {
    if (sp.end_seconds <= sp.start_seconds) add("spanNonPositive", "high", `talk_span end ≤ start at ${fmt(sp.start_seconds)}`);
    if (sp.start_seconds < -TOL || (dur > 0 && sp.end_seconds > dur + TOL)) add("spanOutOfBounds", "high", `talk_span [${fmt(sp.start_seconds)},${fmt(sp.end_seconds)}] out of [0,${fmt(dur)}]`);
    if (typeof sp.references_subject === "string" && sp.references_subject !== "" && words(sp.references_subject).length > 3)
      add("spanReferencesFormat", "low", `references_subject "${sp.references_subject}" is > 3 words`);
    if (sp.is_to_camera === true) toCamera++;
  }

  // completeness floors
  const depictsCount = shots.filter((s) => typeof s.depicts_subject === "string" && s.depicts_subject.trim() !== "").length;
  if (shots.length && depictsCount === 0) add("noDepictsAtAll", "medium", "no shot has a non-empty depicts_subject (a food video should have b-roll supply)");
  const speechShotSecs = shots.filter((s) => s.has_speech).reduce((a, s) => a + Math.max(0, s.end_seconds - s.start_seconds), 0);
  const spanSecs = spans.reduce((a, sp) => a + Math.max(0, sp.end_seconds - sp.start_seconds), 0);
  if (speechShotSecs > 0 && spanSecs < 0.30 * speechShotSecs) add("speechCoverageThin", "medium", `talk_spans cover ${fmt(spanSecs)}s but has_speech shots span ${fmt(speechShotSecs)}s (< 30%) — speech likely under-indexed`);
  if (shots.some((s) => s.scene_type === "talking-head" && s.has_speech) && toCamera === 0)
    add("talkingShotsButNoToCameraSpans", "medium", "there are talking-head shots with speech but zero is_to_camera talk_spans");

  // optional hand-authored ground truth (completeness as a hard check on the fixture we iterate on)
  if (truth) {
    const hay = [
      ...shots.map((s) => s.depicts_subject),
      ...shots.map((s) => s.topic),
      ...shots.flatMap((s) => Array.isArray(s.also_visible) ? s.also_visible : []),
      ...spans.flatMap((sp) => Array.isArray(sp.also_references) ? sp.also_references : []),
    ].map((x) => String(x || "").toLowerCase()).filter(Boolean);
    for (const want of (truth.subjects || [])) {
      const w = String(want).toLowerCase();
      if (!hay.some((s) => s.includes(w) || w.includes(s))) add("missedTruthSubject", "medium", `ground-truth subject "${want}" not found in any shot's depicts_subject/topic`);
    }
    if (truth.toCameraSpanCountMin != null && toCamera < truth.toCameraSpanCountMin)
      add("fewToCameraSpans", "medium", `${toCamera} to-camera spans < expected ${truth.toCameraSpanCountMin}`);
  }

  const penalty = v.reduce((a, x) => a + (x.severity === "high" ? 0.15 : x.severity === "medium" ? 0.07 : 0), 0);
  const score = Math.max(0, Math.min(1, 1 - penalty));
  const tally = Object.entries(v.reduce((m, x) => ((m[x.kind] = (m[x.kind] || 0) + 1), m), {})).map(([k, n]) => `${k}×${n}`).sort().join(", ");
  const summary = v.length ? `score ${fmt(score)} — ${v.length} violation(s): ${tally}` : `Index valid — ${shots.length} shots, ${spans.length} spans, score 1.00`;
  return { score, violations: v, summary, shotCount: shots.length, spanCount: spans.length, depictsCount, toCameraSpans: toCamera, proxyDuration: dur };
}

// Allow `node validate-perceive.mjs runs/howlins/perceive__gemini-2.5-flash__run1/index.json [duration]`
if (import.meta.url === `file://${process.argv[1]}`) {
  const { readFile } = await import("node:fs/promises");
  const file = process.argv[2];
  if (!file) { console.error("usage: node validate-perceive.mjs <index.json> [durationSeconds]"); process.exit(1); }
  const index = JSON.parse(await readFile(file, "utf8"));
  const report = validateIndex(index, Number(process.argv[3]) || 0);
  console.log(report.summary);
  for (const x of report.violations) console.log(`  [${x.severity}] ${x.kind}: ${x.detail}`);
}
