-- Vela — async Gemini analysis jobs.
--
-- The `gemini-proxy` Edge Function is the ONLY reader/writer of this table, using the
-- auto-injected SUPABASE_SERVICE_ROLE_KEY (which bypasses RLS). RLS is enabled with NO
-- policies, so the anon / authenticated roles are fully denied at the table level — an
-- unguessable jobId never leaks another user's row, and the app never touches the table
-- directly (it only calls the function's `analyze` / `status` ops with the anon key).

create table if not exists public.jobs (
  id          uuid primary key default gen_random_uuid(),
  status      text not null default 'active'
              check (status in ('queued','active','generating','done','failed')),
  result      text,            -- verbatim model output (the Edit Plan JSON text); parsed client-side
  error       text,
  file_uri    text not null,   -- Gemini files/... fileUri (passed to generateContent)
  file_name   text not null,   -- Gemini files/... resource name (used for files.get polling)
  mime_type   text not null,
  payload     jsonb not null,  -- full generateContent payload the client assembled (prompt + schema inside)
  model       text not null default 'gemini-2.5-flash',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Supports cleanup of old/terminal rows by age (a later Supabase Cron job).
create index if not exists jobs_created_at_idx on public.jobs (created_at);

alter table public.jobs enable row level security;
-- Intentionally NO policies: locks the table to service-role access only.
