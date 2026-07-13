-- Vela — style-vs-edit push copy: tag each job with what KIND of completion push to send, so the same
-- APNs worker (notifyJobFinished → sendApnsPush) can say "Your cut is ready 🍴" for an edit job and
-- "Your style is ready ✨" for a style-learning job, and route the tap to the right screen.
-- NULLABLE with an implicit 'edit' default in the worker: existing clients that omit `notifyKind` (the
-- edit-plan + PERCEIVE jobs) keep the current edit copy unchanged.
alter table public.jobs add column if not exists notify_kind text;  -- 'edit' (default) | 'style'
