# PERCEIVE Accuracy — Experiment & Testing TODO

_Runnable test plan for improving the Gemini "watch the video" (PERCEIVE) call. Pick up later._
_Companion to §4 of [DISTRIBUTION_PLAN.md](DISTRIBUTION_PLAN.md). Last updated 2026-07-20._

> **Root cause (established):** decoding is already deterministic
> (`temperature: 0, topK: 1, seed: 7` in [GeminiService.swift:533](FoodEditor/Services/GeminiService.swift#L533)),
> and the transcript with word timings + clip starts is already prepended. Mistakes are **not**
> sampling noise. The prime suspect: **no `mediaResolution` / `fps` is set, so Gemini watches the
> proxy at the default ~1 fps** (~180 stills for a 3-min video). Sub-second food shots contribute
> 0–1 frames → root of the documented segmentation instability (16–46 shots on identical input).

> **Standing rule:** No proxy/Gemini calls fired without Daniel's OK (see memory
> `no-gemini-calls-without-permission`). Wiring is code-only; **Daniel runs the calls**, we read
> results together. State call count + purpose before each run.

---

## Failure-mode split (what each lever actually fixes)
- **Missed shots / wrong boundaries / unstable segmentation** → *ingestion* problem → **fps** fixes it.
  Pro does NOT (it sees the same frames).
- **Mislabels / misreads** (waffle-vs-fries class) → *reasoning* problem → **Pro** + **more thinking**.
- **Timestamp drift** → transcript anchors already fight this; higher fps tightens the visual side.

---

## Levers, in priority order

### Lever 1 — Raise sampled frame rate (cheapest, likely biggest win)
- [ ] Add `videoMetadata.fps` to the file part in `generatePayload`
      ([GeminiService.swift](FoodEditor/Services/GeminiService.swift)); thread a value through the
      PERCEIVE path only (not DECIDE — it's text-only).
- [ ] Default candidate: **fps = 5** for ≤4-min proxies.
- Cost: 5 fps on a 3-min video ≈ 230k input tokens ≈ **~$0.07 input on Flash** (vs ~$0.015 @ 1 fps).

### Lever 2 — Raise PERCEIVE thinking budget
- [ ] Currently `thinkingBudget = 8_192` ([GeminiService.swift:77](FoodEditor/Services/GeminiService.swift#L77)).
      Try **16k / 24k**. Often closes much of the gap to Pro cheaply.
- [ ] Note: the existing code comment says "A/B against 0 in the lab" — also A/B **upward**.

### Lever 3 — Try the Pro model on PERCEIVE
- [ ] Swap PERCEIVE model flash-latest → pro-latest as an eval arm only (keep DECIDE as-is).
- Cost: Pro@1fps adds ~$0.15–0.30; Pro@5fps ≈ ~$0.60–0.90/edit — eats margin at a 30-edit tier.

### Lever 4 — `mediaResolution: high` (if fine mislabels persist)
- [ ] Add `mediaResolution: "high"` for more visual tokens per frame — the lever for
      "can't tell fries from a waffle at token resolution".

### Lever 5 — Structural fix (biggest ceiling, most work) — deferred until data justifies
- [ ] Stop asking the model to segment. On-device shot detection (AVFoundation frame-differencing)
      within known clip bounds → hand Gemini a **fixed** shot list to only describe/label.
      Kills segmentation variance by construction. Build only if instability persists after
      fps + model + thinking tuning.

---

## The experiment — 2×2 (+ thinking) matrix in promptlab

Run on **3 representative fixture videos** (include at least one fast-cut, sub-second-shot video —
the hardest case). Score each arm on: shot count stability, boundary accuracy, label accuracy,
timestamp drift.

| Arm | Model | fps | thinking | Approx cost / video |
|---|---|---|---|---|
| A (baseline) | flash | 1 | 8k | ~$0.05–0.10 |
| B | flash | 5 | 8k | ~$0.10–0.15 |
| C | pro | 1 | 8k | ~$0.20–0.35 |
| D | pro | 5 | 8k | ~$0.65–0.95 |
| E (opt.) | flash | 5 | 24k | ~$0.12–0.18 |

- **Base matrix (A–D) on 3 fixtures = ~12 calls (~$1–2).** Adding arm E = +3 calls.
- [ ] Wire fps + thinking + model as promptlab config knobs (code-only).
- [ ] Daniel runs the ~12–15 calls.
- [ ] Read results together; decide.

### Hypothesis / expected read
- **flash@5fps (B)** fixes most boundary/miss errors — likely the winner on value.
- **pro@5fps (D)** is the quality ceiling — decision is whether its delta over B justifies the cost.
- If B ≈ D on boundaries but D wins on labels → labels are the reasoning-bound part; consider E or
  `mediaResolution: high` before paying for Pro in production.

---

## Watch-outs
- [ ] Higher fps = more input tokens **and** more output detail → watch the **65,536 output-token
      cap** ([GeminiService.swift:71](FoodEditor/Services/GeminiService.swift#L71)) for long proxies;
      truncation surfaces as `GeminiError.truncated`.
- [ ] `promptlab` fidelity fixtures reportedly need regen (`template.json` missing per prior notes) —
      confirm fixtures are valid before running the matrix.
- [ ] Keep DECIDE untouched during this experiment — isolate the PERCEIVE variable.

---

## Decision log (fill in after the run)
- Date run:
- Winning arm:
- Shipped config (model / fps / thinking / mediaResolution):
- Cost delta per edit:
- Follow-up (e.g. build Lever 5?):
