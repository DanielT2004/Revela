#!/usr/bin/env node
// Vela prompt lab — RESOLVE CUT. Turns a plan.json (+ the PERCEIVE content index) into a LINEAR, fully-
// resolved storyboard of the ACTUAL edit: each kept shot in playback order, with its trimmed duration, the
// words spoken over it, running timestamps, and any b-roll overlay annotated inline. The judge reads THIS
// instead of imagining the cut from raw plan JSON + the full 237s proxy — which is what made it score the
// same edit 35/95/98. Pure + deterministic; no deps.
//
//   node resolve-cut.mjs runs/howlins/decide__claude-sonnet-4-6-8k__run1/plan.json
//
// Also exported as resolveCut(plan, index) for judge.mjs.

import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const mmss = (s) => `${String(Math.floor(s / 60)).padStart(2, "0")}:${(s % 60).toFixed(1).padStart(4, "0")}`;

/** Words spoken during [a,b] — talk_spans that overlap the window, joined in order. */
function spokenOver(index, a, b) {
  return (index.talk_spans ?? [])
    .filter((sp) => sp.start_seconds < b - 0.05 && sp.end_seconds > a + 0.05)
    .map((sp) => (sp.spoken_text ?? "").trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Resolve a plan into a linear storyboard.
 * Returns { storyboard, totalDuration, keptCount, cutCount, order, flags }.
 * trim_to_seconds is an ABSOLUTE end timestamp (cut dead air at the tail); a shot's played span is
 * [start_seconds, min(trim_to_seconds, end_seconds)].
 */
export function resolveCut(plan, index) {
  const segById = new Map((plan.segments ?? []).map((s) => [s.id, s]));
  const shotById = new Map((index.shots ?? []).map((s) => [s.id, s]));
  const order = plan.final_edit_order ?? [];
  const brollByOver = new Map();
  for (const b of plan.broll_placements ?? []) {
    if (!brollByOver.has(b.over_segment_id)) brollByOver.set(b.over_segment_id, []);
    brollByOver.get(b.over_segment_id).push(b);
  }

  const flags = [];
  const lines = [];
  let clock = 0;

  for (let pos = 0; pos < order.length; pos++) {
    const id = order[pos];
    const seg = segById.get(id) ?? shotById.get(id) ?? {};
    const shot = shotById.get(id) ?? {};
    const natStart = seg.start_seconds ?? shot.start_seconds ?? 0;
    const natEnd = seg.end_seconds ?? shot.end_seconds ?? natStart;
    const trim = seg.trim_to_seconds;
    const playedEnd = (trim != null && trim > natStart) ? clamp(trim, natStart, natEnd) : natEnd;
    const dur = Math.max(0, playedEnd - natStart);
    const trimNote = (trim != null && trim > natStart && trim < natEnd)
      ? ` [trimmed to ${dur.toFixed(1)}s of ${(natEnd - natStart).toFixed(1)}s]`
      : ` [${dur.toFixed(1)}s]`;

    const kind = shot.reaction_kind && shot.reaction_kind !== "none" ? shot.reaction_kind : shot.scene_type ?? "shot";
    const subj = shot.depicts_subject ? ` · ${shot.depicts_subject}` : "";
    const spoken = spokenOver(index, natStart, playedEnd);
    const roleTag = pos === 0 ? "  ⟵ HOOK (first frame)" : pos === order.length - 1 ? "  ⟵ FINAL SHOT" : "";

    lines.push(`[${mmss(clock)}–${mmss(clock + dur)}] shot ${id} (${kind}${subj})${trimNote}${roleTag}`);
    lines.push(`    VISUAL: ${shot.description ?? "(no description)"}`);
    lines.push(`    AUDIO:  ${spoken ? `"${spoken}"` : "(no speech / silent)"}`);

    for (const b of brollByOver.get(id) ?? []) {
      const src = shotById.get(b.broll_segment_id) ?? {};
      const srcKept = segById.get(b.broll_segment_id)?.keep !== false;
      const oa = clock + (b.start_offset_seconds ?? 0);
      const ob = oa + (b.duration_seconds ?? 0);
      lines.push(`    ⤷ B-ROLL ${mmss(oa)}–${mmss(ob)}: silent VISUAL of shot ${b.broll_segment_id} [${src.description ?? "?"}] over this line; base audio keeps playing.${srcKept ? "" : "  ⚠️ source is keep:false → renders as NOTHING"}`);
      if (!srcKept) flags.push(`b-roll source shot ${b.broll_segment_id} is cut (keep:false) — overlay would be blank`);
      if (kind !== shot.scene_type) flags.push(`b-roll covers shot ${id} whose reaction_kind=${shot.reaction_kind} — the face is the payoff`);
    }
    clock += dur;
  }

  const keptCount = new Set(order).size;
  const cutCount = (index.shots ?? []).length - keptCount;
  const last = shotById.get(order[order.length - 1]) ?? {};
  const verdictLast = last.reaction_kind === "verdict";
  if (!verdictLast) flags.push(`final shot ${order[order.length - 1]} is not a verdict (reaction_kind=${last.reaction_kind}) — edit may not end on the rating`);

  const header = [
    `RESOLVED CUT — ${order.length} shots in playback order, ~${clock.toFixed(1)}s total (target ${plan.recommended_duration ?? "?"}s).`,
    `Kept ${keptCount} of ${(index.shots ?? []).length} source shots; ends on shot ${order[order.length - 1]}${verdictLast ? " (verdict ✓)" : ""}.`,
    flags.length ? `AUTO-FLAGS: ${[...new Set(flags)].join("; ")}` : `AUTO-FLAGS: none`,
    ``,
    `This is the LINEAR edit exactly as it will play. Each block is one on-screen shot; ⤷ lines are silent`,
    `b-roll overlays (their video replaces the face while the base audio continues). Judge THIS sequence.`,
    ``,
  ].join("\n");

  return { storyboard: header + lines.join("\n"), totalDuration: clock, keptCount, cutCount, order, flags: [...new Set(flags)], verdictLast };
}

// ---- CLI ----
if (import.meta.url === `file://${process.argv[1]}`) {
  const HERE = dirname(fileURLToPath(import.meta.url));
  const planPath = process.argv[2];
  if (!planPath) { console.error("usage: node resolve-cut.mjs <plan.json> [indexPath]"); process.exit(1); }
  const plan = JSON.parse(await readFile(planPath, "utf8"));
  // Default to the frozen Howlin's index unless one is given.
  const indexPath = process.argv[3] || join(HERE, "runs/howlins/perceive__gemini-2.5-flash__run1/index.json");
  const index = JSON.parse(await readFile(indexPath, "utf8"));
  console.log(resolveCut(plan, index).storyboard);
}
