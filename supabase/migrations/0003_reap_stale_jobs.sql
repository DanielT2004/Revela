-- Reaper: terminalize jobs orphaned at 'active'/'generating' by a worker eviction.
-- The ~150s free-tier wall-clock can kill an edge worker AFTER it flips a job to 'generating'
-- but BEFORE it writes a terminal status (or before the DECIDE self-bail timer fires) — leaving a
-- dead row the client polls for its full 300s. A periodic reaper flips any job stuck past a safe
-- threshold to 'failed', closing the whole orphan class regardless of cause.
--
-- Threshold = 4 minutes. This is safely above the ~150s worker cap and every legit run
-- (8k DECIDE self-bails at 145s / finishes ~133s; PERCEIVE generateContent ~30-120s and its row's
-- updated_at is never stale >~170s while live), so the reaper never kills a running job. Sweeping
-- every minute means a truly-dead row flips to 'failed' by ~T+300s — in time for the client's own
-- 300s poll to see it and fall back, instead of hanging.

create extension if not exists pg_cron;

-- One-time backfill: clean any rows already stuck (e.g. the worker-eviction orphan a11e3e21).
update public.jobs
   set status = 'failed',
       error = 'stale: worker evicted before writing a terminal status (reaper backfill)',
       updated_at = now()
 where status in ('active', 'generating')
   and updated_at < now() - interval '4 minutes';

-- Recurring sweep every minute (idempotent: drop any prior schedule of the same name first).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'reap-stale-jobs') then
    perform cron.unschedule('reap-stale-jobs');
  end if;
end
$$;

select cron.schedule(
  'reap-stale-jobs',
  '* * * * *',
  $reaper$
    update public.jobs
       set status = 'failed',
           error = 'stale: worker evicted before writing a terminal status (reaper)',
           updated_at = now()
     where status in ('active', 'generating')
       and updated_at < now() - interval '4 minutes'
  $reaper$
);
