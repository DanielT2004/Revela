# Vela — CEO State

> Living strategy tracker. The /ceo skill reads this first and updates it after every meaningful decision, progress item, or new data. Keep entries dated. Newest decisions at the top of the log.

## Current phase

**Phase 0 — Survivable by strangers** (started 2026-07-14, target ~4-6 weeks → mid/late Aug 2026)

Goal: a TestFlight build a paying stranger can use without hand-holding, plus the plumbing to measure them.

## Phase 0 checklist (launch-gating items only — reordered 2026-07-15 into the path-to-users sequence)

1. [ ] **Device-test weekend** — one full pass on a physical phone: style learn → Reveal (signature evidence gate) → brief (pre-answered b-roll row) → edit (b-roll coverage + console `Planned b-roll` line) → Polish shelf (set-aside clips) → export; plus voiceover M3 and footage-conservation flows. Bugs → fix list; cosmetics → parked.
2. [ ] Fix autoplay-return bug (Meka's only hard defect — the known user-reported bug MUST die before new users arrive)
3. [ ] Anonymized funnel logging (import → analysis → first export → fifth export) — without it, user testing is a demo, not an experiment
4. [ ] Founding-member paywall screen ($5-10/mo, locked-forever framing; fake-door OK)
5. [ ] Draft recruiting posts + TikTok DM script for BOTH cohorts (Maya: r/Tiktokhelp / TikTok DMs; Sofia: r/UGCcreators)

DE-SCOPED from the launch gate (2026-07-15 CEO ruling — revisit ONLY if the device weekend shows the current UI actively confusing): Cut Card + Breakdown Sheet redesign; remaining Meka polish (Reveal self-pacing, bigger deck cards + scrubbing, Polish reframe controls). "Survivable by strangers" = no bugs + no dead ends, not maximum beauty.

## Gate metrics (Phase 2 target)

- **Fifth-video retention:** of users who export 1 video, % who export 5. Target ≥ ~40%. Currently: no data (n=1 beta tester).
- Paying founding members: 0. Target for Phase 1: 20-30.
- MRR: $0. Quit-job bar: ≥50-75% of take-home, 3+ months consecutive growth.

## Parked list (do not build until noted phase)

- Transitions/crossfades on B-roll cuts — Phase 3+ (polish, not gate-moving)
- AI script assist for VO — Phase 3+ (moat deepener, needs retained users first)
- Montage reproduction in style templates — Phase 4 (capture-only for now)
- Virality backlog (text overlays, loops, zoom, capture coaching) — Phase 3+
- Arrange page retirement — decide during Meka simplicity pass (leaning retire)
- Recent-projects persistence — Phase 1 if testers complain, else Phase 3
- Production key proxy hardening beyond current Supabase proxy — before App Store launch (Phase 3)
- Niche expansion (day-in-the-life, fitness, real estate, restaurants-direct) — Phase 4, gated on Phase 2 pass
- Accounts/sync — Phase 3+

## Competitive watch (reassess if these move)

- Captions/Mirage: closest competitor; iPhone-first AI Edit + food-creators page; watch for plan-review/HITL UX.
- YouTube "Edit with AI": free native raw-footage→Short; watch US rollout depth + quality reports.
- Meta Edits AI assistant (real retention data) — never position the Read as analytics against this.
- CapCut pricing anger ($8→$20): active switcher opening; "no credits, no metering" is our counter-position.

## Decision log

- **2026-07-15 (eve)** — **User-testing readiness ruling: NOT YET — ~2 focused weeks out.** Blockers: (1) zero device testing on everything shipped (style templates v2, signature gate, entire b-roll system, survey row); (2) autoplay-return bug (the KNOWN user-reported defect) still open; (3) no funnel logging / paywall = users would produce anecdotes, not gate data. Path to yes reordered into the checklist above (device weekend → autoplay → logging+paywall → drafts → fire). Cut Card redesign + remaining Meka polish DE-SCOPED from the launch gate. Engineering state: b-roll system COMPLETE and live-validated same day (dial 15→12.7% / 30→19-23% / 45→~30% supply-capped; ZERO duplicate clips after once-each rule + seed guard + brollDuplicateSource validator; duration blowout self-healed 160→122s; validator 1.0 clean arms vs 0.44 dup-heavy) — quality blockers converted to a finite checklist. FREEZE: no more prompt iterations; no M2/M3; nothing from the parked list.
- **2026-07-15** — **"The template answers the survey" adopted as design law** (Daniel spotted the template-vs-survey b-roll contradiction; CEO ruling): anything the template knows, the brief never re-asks — it SHOWS the learned value pre-answered ("B-roll — matching your style (medium) · change for this video?"), override is one tap, per-video only, never sticky, never silently learned into the template. No template → the question stays. REFINED (same day): pre-answered STATEMENT row, NOT a pre-selected choice among the 3 buckets (a visible multiple-choice is still a puzzle; buckets round her style to a preset = averaging-away in UI form). Override options are RELATIVE to her style ("More me / My usual / More food" = template value ± delta), not absolute buckets — relative modifiers compose with the template, absolute ones contradict it. Principle: pre-filled = app asks her to confirm it knows her; pre-answered = app SHOWS it knows her. WHY: a survey that shrinks with use is compounding switching cost aimed at fifth-video retention (the gate); re-asking settled questions violates Maya Test #1/#2; the pre-answered row is the moat made visible on every video. SCOPE: b-roll row now (rides the b-roll fix); audit remaining survey questions against this law during the Meka survey-slimming pass; per-question override-learning loops PARKED to Phase 1+.
- **2026-07-15** — B-roll underfill root-caused + A/B-VALIDATED (memory `broll-underfill-root-cause`): six-link chain (dangling VO rules, SPARSE priority inversion, non-determinism lottery, structural ceiling, Polish pool starvation, cap-no-floor-no-metric). 4 authorized proxy calls: variant = 23.3% of talking covered (vs 7.3% production / ~16% baseline reruns), 0 subject mismatches, byte-identical twice, cleaner dish blocks. v2 tightening (hard numerals) + Swift implementation + Milestone B (pool fix, plannedBrollPct metric, peak clamp) approved direction; Milestone C (code floor augmenter) evidence-gated. Phase-0 legitimate: edit quality is the gate's death mode.
- **2026-07-15** — Signature-line extraction fix scoped (bad Reveal cards: "check them out", "I feel like I'm in New York right now" surfaced as every-video signatures from ~1 sighting). Diagnosis: no evidence/confidence gate before carding + weak lines can poison a HARD pipeline constraint on a polite "Every video" tap. **M1 (evidence gate: card verbatim lines only at code-verified `evidenceCount≥2`; single-video learns get general-style confirms only; honest-absence copy "no catchphrase yet, most creators don't have one") = PHASE 0** — real trust+correctness defect on a moat surface a stranger hits first session; part of "Device-test Style Templates v2". **M2 (watch-list: keep below-bar lines, surface + promote them on a later refine) = PARKED to Phase 1** — payoff only exists for returning users (the retention we're trying to measure, not assume); safe to defer BECAUSE M1 preserves (never deletes) the weak lines, so no signal lost. **M3 (prompt hardening: formula-vs-reaction negatives, generic-CTA blocklist, "zero lines is correct") gated on Daniel approval + promptlab eval — do NOT ride it in with M1.** Guard: don't let M1 balloon into an extraction refactor; smallest gate a stranger survives.
- **2026-07-14** — PERSONA.md adopted (Daniel's call, adapting his research): PRIMARY = Maya R., growth-stage food/travel short-form creator (own-account, 4-7 videos/wk, 2-3 hrs editing each, control-freak-but-time-poor); SECONDARY = Sofia, client-paid food UGC creator (clearest willingness-to-pay per web research); TERTIARY = Tariq, unpaid grinder (Daniel's add — same pains, ~$0 WTP; recruit for feedback/evangelism, track his cohort separately, never design pricing around him). Phase 1 recruits all cohorts; fifth-video retention among PAYERS decides lead positioning. Maya Test (9 rules) is now design law; wired into CLAUDE.md "Who we build for". Noted gap: caption generation is on Maya's MVP must-have list but parked — revisit at Phase 1 if testers confirm.
- **2026-07-14** — /ceo skill created. Strategy locked: one product, sequence (a) food-UGC wedge → (b) HITL plan + Read + style templates as moat → (c) niche expansion post-gate. Phase 0 opened.
- **2026-07-13** — Validation research run (memory `market-validation-research-2026-07`). Verdict: wedge is real but narrow; hobbyist-food positioning weak, UGC-pro positioning strong; fifth-video retention chosen as the gate metric; quit-job bar defined.
- **2026-07-12** — Beta feedback #1 (Meka): "analytics app with an editor attached"; autoplay bug; simplicity direction (memory `beta-feedback-meka`).
