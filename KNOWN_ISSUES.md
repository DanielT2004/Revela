# Known Issues — pipeline hardening backlog

Findings from the **PERCEIVE → DECIDE → ADAPT pipeline audit** (2026‑06‑30 → 07‑01). 11 candidate bugs were
surfaced by a fan‑out sweep, then **adversarially verified against the real code** (each verifier told to
refute by default). **Result: nothing critical** — every finding verified **LOW** or was **refuted**.

> **Update (2026‑07‑01): DECIDE is now Gemini‑2.5‑Pro *synchronous*, and Claude was removed entirely.** So
> every Claude‑DECIDE‑specific finding (duplicate‑DECIDE‑job micro‑race, DECIDE self‑bail, `decideJob`
> orphans, self‑bailed‑resume, re‑attach) is **moot** and dropped below. What remains applies to the
> **PERCEIVE async job** (`analyze`/`runJob`) and the on‑device resume/transcript paths. The `pg_cron` reaper
> (`0003_reap_stale_jobs.sql`) is now the **sole** orphan backstop (the DECIDE self‑bail went with Claude).

## ✅ Shipped / no longer applicable
- **Stale‑job reaper** — `supabase/migrations/0003_reap_stale_jobs.sql` (pg_cron; sweeps `active`/`generating`
  older than 4 min → `failed`). Live; now the only orphan backstop.
- **~~Duplicate DECIDE jobs · self‑bail 145s · eval DECIDE provenance~~** — all Claude‑DECIDE mechanisms,
  **removed** when DECIDE became Gemini‑only sync. There's no async DECIDE job left to duplicate, orphan, or self‑bail.

## ❌ Refuted (verified NOT bugs)
- **`cancellation-proxy-leak`** — CancellationError only fires on `retry()`, which `save()`s a fresh record
  (atomic overwrite); the `.failed` path `clear()`s first. No durable leak.

## 🔧 Deferred hardening — all verified LOW
Each is safe to leave; the reaper + client fallbacks bound the blast radius.

### 1. `proxy-perceive-no-selfbail` — the PERCEIVE async job has no self‑bail
- **Where:** `gemini-proxy` `runJob` `generateContent`. A PERCEIVE run killed by the ~150s wall‑clock orphans
  at `generating`. **Never observed** (historical Flash orphans were the APNs‑stall bug, fixed in v7); the reaper cleans it.
- **Fix:** wrap the `generateContent` fetch in a `Promise.race` against `~145000 - elapsed`, `fail()` on bail.

### 2. ~~`proxy-no-retry-5xx`~~ — ✅ FIXED (2026‑07‑10, proxy v16)
- **Was:** a 503/overloaded from Gemini during `generateContent` was written as a permanent `failed`.
- **Fixed:** `runJob` now retries a transient `429/500/502/503/504` once more with a 500ms backoff — but
  ONLY while another attempt still fits under the ~170s self‑bail deadline, so a slow late failure can't
  orphan the row at `generating`. Terminal codes (400/401/403…) still fail immediately.

### 3. `proxy-retry-double-create` — no idempotency key on job create
- **Where:** `dbInsertJob` + the `analyze` handler. If the insert commits but the response is lost, a
  user‑tapped Retry creates a second job.
- **Fix:** client‑supplied idempotency key (e.g. from `AnalysisCoordinator.signature`) + a UNIQUE constraint.

### 4. `resume-flag-change-mismatch` — resume branches on the live `twoCallPipeline` flag
- `resumePipeline` branches on `FeatureFlags.twoCallPipeline`; `PendingAnalysisJob` doesn't record which
  pipeline produced the persisted raw. Toggling the flag between a kill and its resume → wrong parser → job
  discarded. **DEBUG‑only reachable** (the toggle is `#if DEBUG`, default off in release).
- **Fix:** persist a `twoCall: Bool?` on `PendingAnalysisJob`, branch on it at resume.

### 5. `transcribe-timebase-divergence` — cursor drift on corrupt media
- `TranscriptionService.transcribeClips` vs the `VideoPreprocessor` insert loop: the preprocessor `continue`s
  (without advancing its cursor) if `insertTimeRange` throws; transcription has no equivalent guard, so a clip
  that passes the video‑track check but fails to insert shifts every following word timestamp late. Only bites
  on **corrupt/undecodable** media.
- **Fix:** mirror the merger's skip — guard `dur > 0` (or a dry‑run insertability check) before `cursor += dur`.

### 6. `proxy-fail-throws-orphan` — best‑effort nested catch (by design)
- `runJob` outer catch: if the main call throws after the `generating` write AND the `fail()` PATCH also
  throws, the row is left at `generating`. Deliberate best‑effort idiom; now covered by the reaper.
- **Fix:** none needed; the reaper is the belt‑and‑suspenders. Listed for completeness.

---

## Style-flow audit — 2026‑07‑08 (deferred LOW findings)

From the multi‑agent working‑tree audit — full traces + verifier verdicts in
[docs/audit-2026-07-08/01-bug-findings.md](docs/audit-2026-07-08/01-bug-findings.md). The **beta‑blocking**
findings (style‑flow lost‑result cluster ①–⑤, onboarding freeze ⑧, iCloud picker ⑨, deployment target ⑩)
were **fixed** in the 2026‑07‑09 change; **⑯** (empty style‑profile viability gate) shipped with it. The
items below verified **LOW** and are deferred — none is user‑blocking for a small friends‑beta.

### 7. `style-start-running-no-signature-check` — redone learn can show the wrong video's template
- **Where:** [StyleAnalysisCoordinator.swift](FoodEditor/Services/StyleAnalysisCoordinator.swift) `start()`
  `case .running: return` — no clip‑signature comparison, so a second `start()` with a *different* video while
  a resumed job is in flight silently delivers the first video's template.
- **Mitigated:** the new Home style‑learn card makes a resumed run visible, so the blind double‑start is now
  unlikely. **Fix (later):** when `.running` and the new signature differs, cancel + relaunch (or refuse with a
  visible message) instead of no‑op.

### 8. `apns-token-race-zero-notification` — submit‑time vs completion‑time token gate
- **Where:** `GeminiService.startJob` snapshots `deviceTokenHex` at submit; the client's local‑notification
  fallback checks it again at completion. A token that registers mid‑run → server has none (no push) AND client
  sees one (skips local) → zero notification. Narrow first‑run timing window.
- **Fix (later):** record whether a token was attached to THIS job at submit and gate the local fallback on that
  snapshot, not the live value.

### 9. ~~`edit-fail-double-notification`~~ — ✅ FIXED (2026‑07‑10)
- **Was:** [gemini-proxy/index.ts](supabase/functions/gemini-proxy/index.ts) `fail()` pushes unconditionally,
  while `AnalysisCoordinator`'s failure path posted an *ungated* local notification → two "Analysis hit a snag"
  banners on a token‑bearing device.
- **Fixed:** both `AnalysisCoordinator` failure notifies (live + resume) now use the style path's two‑condition
  gate — silent only when the failure was a server job (`GeminiError.badRequest`, which the worker already
  pushed) AND a device token exists; client‑side failures (compress/parse/viability) still ping locally.

### 10. `stale-notify-contract-comment` — index.ts comment contradicts code (server side only)
- **Where:** [gemini-proxy/index.ts](supabase/functions/gemini-proxy/index.ts) ~L441 comment still says "style
  extraction sends false". The **Swift** half of this was fixed in the 2026‑07‑09 change; the server comment
  remains. Behaviour is correct; the comment is a maintenance trap.
- **Fix (later):** correct the comment on the next proxy deploy.

### 11. ~~`status-404-conflation`~~ — ✅ FIXED (2026‑07‑10, proxy v16 + client)
- **Was:** [gemini-proxy/index.ts](supabase/functions/gemini-proxy/index.ts) `dbGetJob` collapsed a 0‑row
  result and any non‑ok PostgREST fetch to `null` → 404; the client retried 404 as a blip for the full 300s and
  reported a misleading `timedOut`.
- **Fixed:** `dbGetJob` now THROWS on a non‑ok fetch → the `status` handler answers **503** (a transient DB
  error the client keeps retrying), while a genuine 0‑row still returns **404**. `GeminiService.jobStatus` maps
  404 → terminal `.badRequest` (stops the poll immediately with honest "job expired" copy); 503 stays a
  retryable blip. Shipped together (client + proxy are coupled).

### 12. ~~`empty-editplan-ships-as-success`~~ — ✅ FIXED (2026‑07‑10)
- **Was:** [AnalysisCoordinator.swift](FoodEditor/Services/AnalysisCoordinator.swift) `ship()` had no
  minimum‑viability gate; lenient array decode + an all‑pass validator could produce a 0‑clip "cut".
- **Fixed:** `ship()` now builds the `EditPlanStore` and guards `!plan.segments.isEmpty && !store.order.isEmpty`
  (the resolved spine covers the "decodes fine but keeps nothing" case on both pipeline paths), throwing a
  friendly `AnalysisViabilityError` into the normal `.failed` + Retry path.

### 13. `normalizer-trusts-model-duration` — clamp uses model‑reported duration (debug path)
- **Where:** [ContentIndexNormalizer.swift](FoodEditor/Models/ContentIndexNormalizer.swift) clamps shots to the
  model's `duration_seconds` rather than the measured proxy duration (available in scope); an under‑report
  silently amputates later footage. Only on the `twoCallPipeline` path (DEBUG‑only today).
- **Fix (before enabling twoCallPipeline in release):** pass `processed.metadata.duration` into `normalize()`;
  drop zero‑length shots like zero‑length talk spans already are.

### 14. `duplicate-segment-ids-shadowing` — colliding ids silently hide segments (monolith path)
- **Where:** [EditPlan.swift](FoodEditor/Models/EditPlan.swift) `Segment.init` defaults a missing id to 0;
  first‑wins id dictionaries then shadow the duplicates; the validator has no duplicate‑segment‑id rule. Very
  low prob. against the structured schema.
- **Fix (later):** add a `duplicateSegmentId` rule to `EditPlanValidator`; renumber (as the two‑call normalizer
  does) or fail on collision.
