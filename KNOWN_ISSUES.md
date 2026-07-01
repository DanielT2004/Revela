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

### 2. `proxy-no-retry-5xx` — no retry on a transient PERCEIVE 5xx
- A 503/overloaded from Gemini during PERCEIVE is written as a permanent `failed` (user must tap Retry).
- **Fix:** bounded retry (2‑3 attempts, short backoff) on `429/500/502/503/504` before `fail()`.

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
