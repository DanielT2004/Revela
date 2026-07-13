-- Vela — server-side consolidation chaining: push at TRUE completion, not at last-extraction.
--
-- A multi-video style learn's final merge (the N≥2 "find what repeats" Gemini Pro call) used to run
-- CLIENT-side, so the batch push fired when the last extraction landed and the user tapped into ~74s
-- of "Finding what repeats…" (measured 2026-07-11). Now the client authors the complete consolidation
-- payload at submit time — with «VELA_SRC_i» placeholder tokens standing in for the not-yet-extracted
-- per-video results — and the worker that wins the batch latch substitutes the results, inserts a
-- text-only CHAINED job, and hands it to a fresh invocation (internal `chain` op). The push moves to
-- the chained job's completion; the client discovers it via `consolidation_job_id` and just awaits it.
--
--   batch_index          — this job's slot in its batch (which «VELA_SRC_i» its result fills)
--   consolidation        — the client-authored spec { payload, model } (same copy on every sibling;
--                          the latch winner reads its own row's)
--   consolidation_job_id — the chained job, stamped on ALL batch rows so the client (live or
--                          kill-resumed) can find it from any sibling's `status`
alter table public.jobs
  add column if not exists batch_index          int,
  add column if not exists consolidation        jsonb,
  add column if not exists consolidation_job_id uuid;

-- Chained consolidation jobs are text-only — there is no Gemini file to poll — so the file columns
-- the base migration required become nullable. Extraction/edit jobs still always send them.
alter table public.jobs
  alter column file_uri  drop not null,
  alter column file_name drop not null,
  alter column mime_type drop not null;
