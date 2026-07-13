-- Vela — one push per multi-video style learn: a 3-video learn used to fire THREE "Your style is
-- ready ✨" pushes (one per extraction job, each finishing on its own clock — some while the user was
-- still watching the analyzing screen). `batch_id` groups a submission's sibling jobs, `batch_size`
-- tells the worker how many siblings exist, and `batch_notified` is the exactly-once latch: when a
-- batched job reaches a terminal state, the worker only pushes if ALL siblings are done AND it wins the
-- single-statement `update … where batch_notified = false` (two near-simultaneous finishers can't both
-- win). NULLABLE throughout: edit jobs + older clients never send a batch → per-job behavior unchanged.
alter table public.jobs
  add column if not exists batch_id       uuid,
  add column if not exists batch_size     int,
  add column if not exists batch_notified boolean not null default false;

-- Sibling lookups (count done / claim latch) filter on batch_id; partial index keeps it free for the
-- overwhelmingly batch-less edit jobs.
create index if not exists jobs_batch_idx on public.jobs (batch_id) where batch_id is not null;
