# Food-Coupling Assessment — Vela

## 1. Where food-specificity actually lives

**Tier 1 — Prompt text (deepest coupling, ~90% of it)**
- [PerceivePrompt.swift](FoodEditor/Services/PerceivePrompt.swift) — "raw, unedited food-review video" framing; the whole `scene_type` vocabulary (`food-closeup`, `bite-reaction`, `plating`, `ambiance`…); `reaction_kind` (`bite`, `first_taste`, `verdict`, `peak_reaction`); food-only examples ("Chicken Sandwich", cheese pull); `depicts_subject` defined as "the ONE food item or place". The vocabulary is duplicated in `PerceivePrompt.schema` as Gemini `responseSchema` enum lists.
- [DecidePrompt.swift](FoodEditor/Services/DecidePrompt.swift) — "EDITOR of a short-form (TikTok) food video"; hard rules in food terms ("never cover a bite", "PREFER food-closeup shots as b-roll", "per-DISH whole blocks", money shots = "cheese-pull / drip / sizzle").
- [GeminiPrompt.swift](FoodEditor/Services/GeminiPrompt.swift) — legacy analysis prompt + the **style-extraction prompt** (`video_format` types like `single-dish-review | mukbang | trying-viral-foods`, `keeps_natural_food_sounds`, beat examples "introduce restaurant", "first-bite reaction").
- [BriefPromptBuilder.swift](FoodEditor/Services/BriefPromptBuilder.swift) / [StyleConstraintBuilder.swift](FoodEditor/Services/StyleConstraintBuilder.swift) — only ~1 food mention each (mostly neutral).

**Tier 2 — Schema enums + code logic keyed on them (the structural coupling)**
- [EditPlan.swift](FoodEditor/Models/EditPlan.swift) `SceneType` — 7 food-shaped cases, but with `.unknown` fallback so foreign vocab never crashes decode. Everything else in `EditPlan`/`Segment`/`BrollPlacement` is vertical-neutral (ids, times, hook_score, topic, section).
- Logic branching on food cases (~6 sites): [EditPlanStore.swift](FoodEditor/Models/EditPlanStore.swift) `isFoodCloseup` seeds the B-roll pool (lines 103, 122, 237, 241); [EditPlanRepair.swift](FoodEditor/Models/EditPlanRepair.swift) ranks `.foodCloseup` +100 as replacement B-roll; [TriageView.swift](FoodEditor/Views/TriageView.swift#L21) buckets `.foodCloseup` → B-roll; [RetentionRead.swift](FoodEditor/Models/RetentionRead.swift#L200) hook copy per scene type. (The `talkingHead` checks in Validator/Adapter are actually vertical-neutral — "face vs. coverage".)
- [EditBrief.swift](FoodEditor/Models/EditBrief.swift) — `HookShot` options (`foodCloseup`, `biteReaction`, `plating`, `finalDish`) and their prompt-fragment strings.
- [StyleTemplate.swift](FoodEditor/Models/StyleTemplate.swift) — `deriveName`/`makeDefaultHabits` emit food copy ("Punch-in on the first bite", "Keep the sizzle audio"); mirrors the extraction schema's food enums.

**Tier 3 — UI copy (shallow, ~a dozen strings)**
TriageView "A clean food shot…", BriefView "~25–35s tends to perform best for food reviews", FirstCutView "food fills the phone", RetentionRead band copy ("food videos tend to hold…", "the bite/verdict lands…"), AnalyzingStepView "you cut right on the bite", `SceneType.label`.

**Tier 4 — Design system + naming (cosmetic)**
[FoodGradients.swift](FoodEditor/DesignSystem/FoodGradients.swift) `FoodTone` (cheese/tomato/herb/…) — the *names* are food; the warm palette itself is vertical-agnostic. `SceneType.foodTone` mapping. Module/target name `FoodEditor`, `FoodEditorApp`.

**Explicitly NOT food-coupled (the good news)**
- The entire render spine: `EditPlanStore` two-layer model, `renderSlots()`/audio pieces, [EditPlanAssembler.swift](FoodEditor/Assembly/EditPlanAssembler.swift), PolishComposition, SourceSpan mapping, export.
- The whole backend: [gemini-proxy/index.ts](supabase/functions/gemini-proxy/index.ts) is a model-agnostic passthrough + job runner + APNs (zero food strings), migrations, StyleJobStore/AnalysisJobStore, kill-recovery.
- [TopicGrouping.swift](FoodEditor/Models/TopicGrouping.swift) — already fully generic ("a dish… or any chapter"); `topic` works unchanged for "The Offer" or "Morning Routine".
- Transcription, preprocessing, navigation, all gesture/motion machinery.

## 2. What a second vertical (e.g. talking-head/marketing) forces you to change

1. **New PERCEIVE + DECIDE prompt bodies** — the big, unavoidable cost. These are empirically tuned (promptlab A/B, 92–95 postable scores); a new vertical needs its own eval cycle, not string substitution. Scene vocabulary, `reaction_kind`, narrative arc ("per-dish blocks", "verdict last") and money-shot definitions are all food-idiomatic.
2. **`SceneType` vocabulary** + the duplicated `responseSchema` enum lists in `PerceivePrompt.schema` / `GeminiPrompt`.
3. **The ~6 logic sites** above — mainly "what counts as a B-roll source" (currently `== .foodCloseup`) and Triage bucketing.
4. **Style-learning stack**: extraction prompt's `video_format`/beat examples, `StyleTemplate` derived names/default habits, `EditBrief` hook options + prompt fragments.
5. **~12 UI copy strings** and `RetentionRead` band copy.
6. **Nothing else** — assembly, preview, stores, server, push, persistence all carry over untouched.

## 3. Recommendation: how to go multi-vertical later without slowing food now

**The architecture is already ~85% there.** The Edit Plan contract (ids/times/order/overlays) is vertical-neutral; the only structural leak is `SceneType` + the handful of predicates on it.

**When (and only when) vertical #2 is real**, introduce a single `Vertical` config value injected at analysis time, owning:
- the PERCEIVE/DECIDE prompt bodies + schema enum lists (each vertical's prompts are separately eval'd artifacts, swapped whole);
- a scene vocabulary (raw strings) + two role predicates: `isBrollSource(SceneType)` and `isFace(SceneType)` — that's all the app logic actually needs;
- `HookShot`/brief options, the ~12 copy strings, and a tone palette name-map.
`.unknown`-tolerant decoding means foreign scene values already can't crash anything.

**Cheap hygiene worth doing now (near-zero cost):**
- Keep new logic role-named, not food-named: route future `.foodCloseup` checks through the existing `isFoodCloseup(_:)` helpers in `EditPlanStore` (a later rename to `isBrollSource` is one line) instead of scattering fresh `== .foodCloseup` comparisons.
- Keep the server a passthrough — it's clean today; never push scene vocabulary into `gemini-proxy` or the jobs table.

**What NOT to abstract yet (explicitly):**
- **Do NOT template the prompts** with `{{vertical}}` placeholders. Prompt quality is empirical per vertical; the tested food prompts are frozen artifacts (CLAUDE.md: never change without the user), and a generic prompt would be worse for food *and* untested for everything else.
- **Do NOT genericize `SceneType`** into abstract roles ("subject-closeup") now — it would churn the tested Gemini schema, the validator/repair self-tests, and saved plans, for zero food-MVP benefit.
- **Do NOT rename** the `FoodEditor` module, `FoodTone`, or app branding — pure churn, pbxproj risk, no user value.
- **Do NOT build a vertical registry/protocol/plugin system** — with n=1 verticals you'd be guessing the axis of variation; the config-object shape above falls out naturally once a second prompt set exists.
- **Do NOT make the design system configurable** — Warm Editorial works for lifestyle/talking-head as-is; revisit only if a vertical demands a different mood.

**Bottom line:** food-specificity is concentrated in swappable *content* (2 prompt bodies + enum vocab + ~12 strings), not in *structure*. The render pipeline, job system, and Edit Plan contract are already vertical-agnostic. The right move is discipline (role-named predicates, clean server) now, and a per-vertical prompt+vocab+copy bundle later — budget the real cost as a promptlab eval cycle per new vertical, not an engineering refactor.