# Vela Eval & A/B Strategy (solo dev, no users yet)

Everything below builds on what already exists: `tools/promptlab/` (run/judge/ab-report, `lib/validate.mjs` mirroring [EditPlanValidator.swift](FoodEditor/Models/EditPlanValidator.swift)), on-device capture via [EvalArtifactStore.swift](FoodEditor/Services/EvalArtifactStore.swift), and the `fixtures/*.truth.json` pattern. The goal is to *extend*, not rebuild.

---

## 1. Frozen golden set

**What to freeze.** Two artifacts per video, not one:
- **Frozen proxy bytes** (already the promptlab convention) — isolates prompt changes from encoder noise.
- **Frozen canonical PERCEIVE index** (`index.json`, already produced by `run-perceive.mjs`) — this is the key move against Flash's 16–46-shot instability. DECIDE experiments run against the *frozen index*, so DECIDE variance is only decode sampling, not segmentation roulette.

**Truth files — key to TIME, not shot ids.** Extend `howlins.truth.json` (currently subjects + span-count floor) with human labels expressed as **second ranges**, because shot ids are not stable across PERCEIVE runs:

```json
{
  "hook_acceptable": [[102.0,106.5],[3.0,5.0]],   // any of these ranges opening = correct hook
  "must_keep":       [[131.0,134.0],[88.5,91.0]], // money shots (bite, cheese pull, verdict)
  "must_cut":        [[0.0,6.2],[201.0,209.0]],   // dead air, false starts, camera fumbles
  "verdict":         [[229.0,236.0]],
  "dish_blocks":     {"Chicken Sandwich":[[60,140]], "Waffles":[[140,180]]},
  "duration_ok":     [40, 65]
}
```
Score any run against truth by **overlap (IoU ≥ 0.5)** of its kept/placed shots with these ranges — works for both the frozen index and fresh Flash runs. Truth authoring cost: ~20 min per video with the app's own triage UI + a stopwatch; do it once.

**How many videos.** **8–12 frozen proxies** is enough for a solo dev; more than that and you'll stop running the suite. Cover the failure taxonomy, one or two each: single-dish review, multi-dish spread (the waffle/fries confusion class), recipe/cook-along, footage shot out of order, weak-hook footage (no bold claim anywhere), long (>3 min) footage that stresses MAX_TOKENS, noisy-audio, and one "friend-shot" clip that isn't your own style. Source: your own shoots + friends' camera rolls; harvest via **EVAL LAB → Share runs** (note: `pruneRuns` keeps only the latest bundle — export immediately after each capture).

**How many repeats given Flash variance.**
- **DECIDE-only change** (frozen index): 3 seeded runs per cell per video (`run1..3`, as the existing `decide__*__run{1,2,3}` dirs already do). Low temp → medians are stable.
- **PERCEIVE or end-to-end change**: 5 runs per video per variant. Flash's segmentation variance *is* the distribution you're measuring; report median + min/max, never a single run.
- Cost sanity: 10 videos × 2 variants × 5 runs ≈ 100 DECIDE calls ≈ **$3**, plus pennies for Flash and judge passes. Run the full matrix freely; the constraint is your reading time, not money.

---

## 2. Metrics (no TikTok posts required)

Tier them by trust. Objective-from-truth beats objective-from-Flash beats LLM judge.

**Tier 1 — mechanical (already mostly built, per run):**
- **Parse/schema validity rate** — plan.json exists; plus `rawLooksComplete` from meta.json (MAX_TOKENS fingerprint).
- **Repair-trigger rate** — `validation_ai.json` (pre-repair) vs `validation.json`: how often the model breaks rules that code must fix, broken down by `Violation.kind`. A prompt that halves `brollSourceNotKept` is a win even if judge scores tie.
- **Validator score** (0–1 weighted) — the existing objective backbone.
- **Duration error** — |`resolveCut` totalDuration − brief target| (ab-report already prints this).
- Distribution guardrails: kept-count, b-roll count, PERCEIVE shot count (flag <15 or >45), coverage gaps, **verbatim transcript match rate** for `spoken_text` (you have ground-truth transcripts — cheap string comparison, catches Flash paraphrasing).

**Tier 2 — truth-file metrics (new, ~50 lines in a `score-truth.mjs`):**
- **Hook agreement**: opening shot's range overlaps any `hook_acceptable` range (binary). Track per-video; this is your single most important number.
- **Dead-air seconds remaining**: seconds of the resolved cut overlapping `must_cut` ranges. Target: 0.
- **Money-shot recall**: fraction of `must_keep` ranges present in the cut.
- **Ends-on-verdict** (binary) and **rating-leaked-to-cold-open** (binary) — direct checks on the two hard narrative rules in [DecidePrompt.swift](FoodEditor/Services/DecidePrompt.swift).
- **Dish interleaving count**: topic sequence A→B→A transitions (should be 0 per the whole-blocks rule).
- **Mid-sentence trim rate**: trims landing >0.3s inside a talk_span rather than at its end.

**Tier 3 — human postability rubric (you, blind).** Formalize your current "2.5 of 3" gut call:
- **1** broken/unwatchable · **2** needs full manual re-edit · **3** postable after 5–10 min in-app fixing · **4** postable after ≤2 tweaks · **5** post as-is.
- Grade the *resolved storyboard + a quick app preview*, with variant labels shuffled (a 10-line script that renames cells to A/B and keeps the key). Log to a CSV next to `summary.csv`. "Postable rate" = fraction ≥4. This is the metric everything else must ultimately correlate with.

---

## 3. A/B-ing prompt variants cheaply

**Design: always paired.** Same frozen proxy + same frozen index → variant A and B. Between-video variance dwarfs between-variant variance, so compare **per-video deltas**, never pooled means. The existing `@extends baseline.txt` mechanism keeps diffs reviewable.

**Decision rule (skip the stats software):**
- A variant ships if it **wins or ties on ≥8 of 10 videos** (sign test: 8/10 wins ≈ p≈0.05) on the primary metric for that experiment, **and** introduces zero new Tier-1/Tier-2 hard-fails on videos that previously passed. One regression on a previously-clean video = investigate before shipping, regardless of the average.
- Pick **one primary metric per experiment** before running (hook change → hook agreement; pacing change → dead-air + judge retention_pacing). Everything else is a guardrail.
- **Treat judge `overall` deltas < ~8 points as noise.** Your own `judge.json` spreads (overall_min–max across 5 passes) show single-run swings of that size; the old judge scored one edit 35/95/98. Small effects must be proven by Tier-1/2 metrics, not the judge.

**LLM judge — keep it, but know its lies.** The v2 design (resolved storyboard, median-of-5, seeded, hard-fail anchors, cite-shot-ids) is genuinely good. Distrust list:
- **It now grades its own family.** The judge.mjs comment says "deliberately not Claude so it isn't grading its own family" — but DECIDE *is now gemini-2.5-pro* (Claude removed). Self-preference bias is live. Mitigation: keep the anchors tied to objectively checkable facts (opens silent, ends on verdict, b-roll covers reaction — all verifiable from the storyboard), and re-weight your trust toward Tier 2. Optionally add a second judge model for tie-breaks on close calls only.
- **It can't see pixels or hear delivery**: a blurry, badly-lit "money shot" scores 5; flat vocal delivery on a "bold claim" scores 5. Storyboard fidelity is bounded by PERCEIVE's descriptions — a PERCEIVE mislabel poisons the judge silently.
- **Verbosity/reason bias**: plans with richer `reason` strings read better. Consider stripping `reason` fields from the storyboard the judge sees.
- **Calibration ritual**: monthly (or per 20 judged cells), human-score 10 storyboards on the 1–5 rubric and check rank agreement with judge overall. If the judge stops ordering things the way you do, fix the rubric before trusting another A/B. Pin judge model + prompt hash into `judge.json` so old CSVs stay interpretable.

**Testing PERCEIVE variants** (the unstable half): run each variant's indexes through the **same frozen DECIDE prompt** and compare downstream Tier-2 metrics, plus direct index metrics (shot-count spread across 5 runs, truth-subject completeness as in `howlins.truth.json`, transcript verbatim rate, boundary sanity). A PERCEIVE prompt that narrows the 16–46 spread to 20–30 is a win even at equal downstream quality.

---

## 4. ~10 friends testing: implicit signals

Don't instrument every gesture. Capture **two plans and a few counters** per project, uploaded as one JSON blob to Supabase (you already have the client + a jobs table; add an `eval_events` table, RLS on, no video bytes, opt-in toggle next to the existing capture toggle):

- **`model_plan`** (as shipped by DECIDE, post-repair) and **`final_plan`** (as exported). The diff between them *is* the disagreement signal — compute everything offline:
  - **Triage flips**: model-keep→user-cut and model-cut→user-keep, each with `scene_type`, `reaction_kind`, `hook_score`. Aggregate flip rate *by category* — "users cut 70% of the ambiance shots the model keeps" is a prompt rule waiting to be written.
  - **Hook overridden** (user changed `hookId`) — the strongest single disagreement bit; it's the same construct as your Tier-2 hook agreement, now from other humans.
  - **Reorder distance** (Kendall tau between model order and exported order), trims added/changed, b-roll placements deleted/moved (b-roll survival rate).
- **Counters**: seconds in triage / timeline / polish (time-in-polish ≈ "how far from postable"), and the **funnel**: analysis done → triage done → export done → saved. Export completion is your best proxy for postability from people who aren't you.
- **Escalation path**: any project where the user flipped >30% of decisions or spent >10 min in polish → ask that friend for the run bundle (EvalArtifactStore already packages it) → add the proxy to the golden set with fresh truth labels. Field failures become frozen regression tests.

**Feedback loop discipline**: field signals *propose* prompt changes; the frozen golden A/B (§3) *disposes*. Never ship a prompt tweak straight from a friend anecdote — with n≈10, one loud friend is 10% of your data.

---

## 5. Later: real TikTok posts

Reality check: the public TikTok APIs give views/likes/comments/shares, but the **retention curve and average-watch-time live only in the Creator analytics UI** — plan for manual entry, not OAuth plumbing:

- On export, you already have the plan blob; add an `export_id`. Later, a tiny "how did it do?" form (in-app or a spreadsheet) keyed by export thumbnail: **views, average watch time, % viewers past 3s, full-watch %** — four numbers the creator reads off their analytics screen in 30 seconds.
- Map them to your offline metrics: 3s-survival ↔ hook agreement / hook_strength; avg-watch% ↔ retention_pacing + dead-air; shares/saves ↔ money-shot recall / payoff_verdict.
- **Use posts to calibrate, not to A/B.** You'd need hundreds of posts to A/B prompts on view metrics (creator, dish, and posting-time confounds swamp everything). With the first ~30–50 posts, just check rank correlation: does judge `overall` (and your 1–5 rubric) order videos the same way watch% does? If yes, your whole offline stack is validated and stays the fast iteration loop. If a specific rule (e.g. cold-open verdict tease) shows up on both sides of a natural experiment, that's a bonus, not the plan.

---

## Operating rhythm (one person)

- **Per prompt idea (~1 hr, ~$3–5)**: write `prompts/<idea>.txt` with `@extends`, run the matrix on the golden set, read `ab-report.mjs` head-to-head + `score-truth` deltas, apply the ≥8/10 rule, blind-grade 1–5 only if Tier 1/2 is ambiguous.
- **Weekly**: re-run baseline on the full set once (catches silent model-version drift server-side — you don't control when Google moves `gemini-2.5-pro`); skim friend flip-rate aggregates.
- **Monthly**: judge↔human calibration check; promote 1–2 field-failure videos into the golden set (cap the set ~15; retire redundant ones).
- **Don't build**: dashboards, auto-retraining, per-gesture analytics, TikTok OAuth. The CSVs + a truth scorer + your blind rubric are the whole platform.

**Small immediate gaps to close**: (1) `score-truth.mjs` + richer truth files (biggest missing piece — turns "2.5 of 3 feels postable" into per-rule regression tests); (2) blind-label shuffler for the 1–5 rubric; (3) `eval_events` table + the two-plan upload; (4) note in judge.mjs that the judge/DECIDE self-family caveat now applies.