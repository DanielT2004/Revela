# gemini-proxy

Server-side proxy for the Google Gemini Files API so `GEMINI_API_KEY` never ships
in the Vela iOS binary. See the header of [index.ts](index.ts) for the contract.

As of the **async job runner** milestone it does two jobs:

1. **Key relay** (`start` / `poll` / `generate`) — forwards single key-bearing calls (legacy path).
2. **Async analysis jobs** (`analyze` / `status`) — `analyze` records a row in the `jobs` table
   (see [../../migrations/0001_jobs.sql](../../migrations/0001_jobs.sql)), returns a `jobId`
   immediately, and runs poll-until-ACTIVE → `generateContent` → response-extraction **server-side**
   via `EdgeRuntime.waitUntil`, writing the result back to the row. The app polls `status`. This is
   what lets analysis keep running after the user closes the app. The `jobs` table is **service-role
   only** (RLS on, no policies); the app never touches it directly — it only calls these two ops with
   the anon key. `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` are auto-injected — **no new secret**.

## One-time setup

```bash
# 1. Install the CLI (once) and sign in
brew install supabase/tap/supabase
supabase login

# 2. Link this repo to your Supabase project (grab <project-ref> from the
#    dashboard → Project Settings → General → "Reference ID")
supabase link --project-ref <project-ref>

# 3. Store the Gemini key as a server secret (NEVER commit it; this is the only
#    place the key now lives). Get one at https://aistudio.google.com/apikey
supabase secrets set GEMINI_API_KEY=your-real-gemini-key

# 4. Apply the database migration (creates the `jobs` table for the async runner).
supabase db push

# 5. Deploy. Leave JWT verification ON (do NOT pass --no-verify-jwt) so the
#    function requires the app's anon key.
supabase functions deploy gemini-proxy
```

## Wire the app to it

In `Secrets.xcconfig` (gitignored — copy from `Secrets.example.xcconfig`):

```
SUPABASE_PROJECT_REF = <project-ref>          # same ref as above, e.g. abcdefghijklmnop
SUPABASE_ANON_KEY    = <anon public key>      # dashboard → Project Settings → API → "anon public"
```

The app builds the endpoint as
`https://<SUPABASE_PROJECT_REF>.supabase.co/functions/v1/gemini-proxy` and sends the
anon key on every call. (We store the ref, not the full URL, because xcconfig treats
`//` in a value as a comment.)

## Test from the CLI

```bash
# Should return 200 + {"error":"start requires a positive numBytes"} (auth passed, op reached)
curl -i -X POST \
  "https://<project-ref>.supabase.co/functions/v1/gemini-proxy" \
  -H "Authorization: Bearer <anon-key>" \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"op":"start"}'

# Without the anon key → 401 from the gateway (function never runs)
curl -i -X POST "https://<project-ref>.supabase.co/functions/v1/gemini-proxy" -d '{}'
```

## Smoke-test the async job runner

```bash
# Validation only (no real file) → 400, proves the op + table wiring is reachable:
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/gemini-proxy" \
  -H "Authorization: Bearer <anon-key>" -H "apikey: <anon-key>" -H "Content-Type: application/json" \
  -d '{"op":"analyze"}'
# -> {"error":"analyze requires fileUri, fileName, mimeType and a payload object"}

# Unknown job id → 404 (proves the service-role SELECT path works):
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/gemini-proxy" \
  -H "Authorization: Bearer <anon-key>" -H "apikey: <anon-key>" -H "Content-Type: application/json" \
  -d '{"op":"status","jobId":"00000000-0000-0000-0000-000000000000"}'
# -> {"error":"job not found"}

# Full path (needs a real ACTIVE Gemini fileUri/fileName from a prior start+upload, and a payload):
#   analyze -> {"jobId":"..."}   then poll status until {"status":"done","result":...} or "failed".
```
