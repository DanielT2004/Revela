// Vela — Gemini Files API proxy (Supabase Edge Function, Deno).
//
// Purpose: keep GEMINI_API_KEY off the device. The iOS app no longer ships the
// key — it calls this function, which injects the key (stored as a Supabase
// secret) and forwards to Google's Generative Language API.
//
// Only the three KEY-BEARING control-plane calls are proxied. The heavy
// 5–50 MB proxy-video upload is NOT here: Google's resumable session URL is
// itself the credential, so the app PUTs the bytes phone→Google directly. We
// never stream video through this function.
//
// Ops (JSON body `{ "op": ..., ... }`):
//   start    { numBytes, mimeType?, displayName? }           -> { uploadUrl }          (key-bearing)
//   poll     { name }                                         -> Gemini file JSON (verbatim)
//   generate { payload, model? }                              -> generateContent JSON (verbatim)
//   analyze  { fileUri, fileName, mimeType, payload, model? } -> { jobId }              (async job)
//   status   { jobId }                                        -> { status, result?, error? }
// Any other op is rejected — this is an allowlist, not an open pass-through.
//
// ASYNC JOB RUNNER (analyze/status): the heavy poll-until-ACTIVE + generateContent +
// response-extraction loop used to run on the phone, so backgrounding the app killed it. Now
// `analyze` records a row in the `jobs` table, returns its id immediately, and finishes the work
// AFTER the HTTP response via `EdgeRuntime.waitUntil` — so it survives the client closing. The app
// polls `status` (and re-attaches on relaunch). The `jobs` table is service-role-only (see the
// 0001_jobs.sql migration); the client never touches it directly.
//
// Auth: JWT verification stays ON (deploy WITHOUT --no-verify-jwt). The Supabase
// gateway requires the app's anon key before this code runs. That blocks casual
// abuse only — the anon key still ships in the app.
// TODO (accounts milestone): per-user Supabase Auth + rate-limit / quota here.

// `EdgeRuntime` is a Supabase Edge runtime global (no import); declared so TypeScript is happy.
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

const GEMINI_BASE = "https://generativelanguage.googleapis.com";

// Auto-injected into every deployed Edge Function — the async job runner uses these to read/write
// the `jobs` table with service-role access (which bypasses RLS). Empty only in a bare local run.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

// Pass Gemini's response straight back to the client — same status, same JSON body —
// so the app's existing error handling (HTTP code + body) keeps working unchanged.
function passthrough(text: string, status: number): Response {
  return new Response(text, {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

// --- jobs table access (PostgREST, service role bypasses RLS — no Supabase SDK) ----------------

function dbHeaders(): Record<string, string> {
  return {
    "apikey": SERVICE_ROLE,
    "Authorization": `Bearer ${SERVICE_ROLE}`,
    "Content-Type": "application/json",
  };
}

async function dbInsertJob(row: Record<string, unknown>): Promise<string> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/jobs`, {
    method: "POST",
    headers: { ...dbHeaders(), "Prefer": "return=representation" },
    body: JSON.stringify(row),
  });
  if (!r.ok) throw new Error(`insert jobs failed: ${r.status} ${await r.text()}`);
  const [created] = await r.json();
  return created.id as string;
}

async function dbUpdateJob(id: string, patch: Record<string, unknown>): Promise<void> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/jobs?id=eq.${id}`, {
    method: "PATCH",
    headers: dbHeaders(),
    body: JSON.stringify({ ...patch, updated_at: new Date().toISOString() }),
  });
  if (!r.ok) throw new Error(`update jobs failed: ${r.status} ${await r.text()}`);
}

async function dbGetJob(
  id: string,
): Promise<{ status: string; result: string | null; error: string | null } | null> {
  const r = await fetch(
    `${SUPABASE_URL}/rest/v1/jobs?id=eq.${id}&select=status,result,error`,
    { headers: dbHeaders() },
  );
  if (!r.ok) return null;
  const rows = await r.json();
  return rows[0] ?? null;
}

// --- the async analysis worker (runs AFTER the HTTP response, via EdgeRuntime.waitUntil) --------
//
// This is the loop that used to run on the phone: poll files.get until ACTIVE, call
// generateContent, then extract the candidate text EXACTLY as GeminiService.generate() did
// (blockReason check → join candidates[0].content.parts[].text → empty ⇒ fail with finishReason).
// The result text is stored verbatim in jobs.result; the client still runs EditPlan.parse on it.
async function runJob(
  jobId: string,
  fileName: string,
  payload: unknown,
  model: string,
  key: string,
): Promise<void> {
  try {
    // Step 1 — poll files.get until ACTIVE (mirrors waitUntilActive). ~170s budget so we self-bail
    // to 'failed' BEFORE the runtime's wall-clock cap rather than orphaning the row at 'active'.
    const deadline = Date.now() + 170_000;
    let state = "";
    while (Date.now() < deadline) {
      const g = await fetch(`${GEMINI_BASE}/v1beta/${fileName}?key=${key}`);
      if (!g.ok) {
        await dbUpdateJob(jobId, { status: "failed", error: `poll HTTP ${g.status}: ${(await g.text()).slice(0, 300)}` });
        return;
      }
      const f = await g.json();
      state = f.state ?? "";
      if (state === "ACTIVE") break;
      if (state === "FAILED") {
        await dbUpdateJob(jobId, { status: "failed", error: "Gemini failed to process the uploaded video." });
        return;
      }
      await new Promise((res) => setTimeout(res, 2000));
    }
    if (state !== "ACTIVE") {
      await dbUpdateJob(jobId, { status: "failed", error: "Timed out: file never became ACTIVE." });
      return;
    }

    // Step 2 — generateContent (the long call). Forward the client's payload verbatim.
    await dbUpdateJob(jobId, { status: "generating" });
    const g = await fetch(`${GEMINI_BASE}/v1beta/models/${model}:generateContent?key=${key}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const text = await g.text();
    if (!g.ok) {
      await dbUpdateJob(jobId, { status: "failed", error: `Gemini HTTP ${g.status}: ${text.slice(0, 300)}` });
      return;
    }

    // Step 3 — extract the model text EXACTLY as the Swift client did.
    let parsed: {
      promptFeedback?: { blockReason?: string };
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> }; finishReason?: string }>;
    };
    try {
      parsed = JSON.parse(text);
    } catch {
      await dbUpdateJob(jobId, { status: "failed", error: "Gemini returned non-JSON." });
      return;
    }

    const block = parsed?.promptFeedback?.blockReason;
    if (block) {
      await dbUpdateJob(jobId, { status: "failed", error: `Gemini returned no usable text (blocked: ${block}).` });
      return;
    }

    const out = (parsed?.candidates?.[0]?.content?.parts ?? [])
      .map((p) => p?.text ?? "")
      .join("");
    if (!out) {
      const finish = parsed?.candidates?.[0]?.finishReason ?? "none";
      await dbUpdateJob(jobId, { status: "failed", error: `Gemini returned no usable text (finishReason: ${finish}).` });
      return;
    }

    await dbUpdateJob(jobId, { status: "done", result: out });
  } catch (_e) {
    // Best-effort terminal state so the client's poll doesn't hang on a silent worker crash.
    try {
      await dbUpdateJob(jobId, { status: "failed", error: "Analysis worker failed." });
    } catch { /* swallow — nothing more we can do */ }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return json({ error: "Server is missing the GEMINI_API_KEY secret" }, 500);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const op = body.op;

  try {
    switch (op) {
      // 1a — open a resumable upload session; hand the keyless session URL back to the app.
      case "start": {
        const numBytes = body.numBytes;
        const mimeType = typeof body.mimeType === "string" ? body.mimeType : "video/mp4";
        const displayName = typeof body.displayName === "string" ? body.displayName : "vela-merged";
        if (typeof numBytes !== "number" || numBytes <= 0) {
          return json({ error: "start requires a positive numBytes" }, 400);
        }
        const g = await fetch(`${GEMINI_BASE}/upload/v1beta/files?key=${key}`, {
          method: "POST",
          headers: {
            "X-Goog-Upload-Protocol": "resumable",
            "X-Goog-Upload-Command": "start",
            "X-Goog-Upload-Header-Content-Length": String(numBytes),
            "X-Goog-Upload-Header-Content-Type": mimeType,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ file: { display_name: displayName } }),
        });
        if (!g.ok) return passthrough(await g.text(), g.status);
        const uploadUrl = g.headers.get("x-goog-upload-url");
        if (!uploadUrl) return json({ error: "Gemini did not return an upload URL" }, 502);
        return json({ uploadUrl });
      }

      // 2 — poll files.get until ACTIVE (the app runs the loop; each call is short).
      case "poll": {
        const name = body.name;
        if (typeof name !== "string" || !name) {
          return json({ error: "poll requires a file name" }, 400);
        }
        const g = await fetch(`${GEMINI_BASE}/v1beta/${name}?key=${key}`);
        return passthrough(await g.text(), g.status);
      }

      // 3 — generateContent (the long one, ~30–120s). Forward the app's full payload.
      case "generate": {
        const payload = body.payload;
        if (payload == null || typeof payload !== "object") {
          return json({ error: "generate requires a payload object" }, 400);
        }
        const model = typeof body.model === "string" ? body.model : "gemini-2.5-flash";
        const g = await fetch(
          `${GEMINI_BASE}/v1beta/models/${model}:generateContent?key=${key}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
          },
        );
        return passthrough(await g.text(), g.status);
      }

      // 4 — analyze: record a job, return its id immediately, finish the work server-side (poll +
      //     generate + extract) via EdgeRuntime.waitUntil so it survives the client closing the app.
      case "analyze": {
        const fileUri = body.fileUri;
        const fileName = body.fileName;
        const mimeType = body.mimeType;
        const payload = body.payload;
        const model = typeof body.model === "string" ? body.model : "gemini-2.5-flash";
        if (
          typeof fileUri !== "string" || !fileUri ||
          typeof fileName !== "string" || !fileName ||
          typeof mimeType !== "string" || !mimeType ||
          payload == null || typeof payload !== "object"
        ) {
          return json({ error: "analyze requires fileUri, fileName, mimeType and a payload object" }, 400);
        }
        if (!SUPABASE_URL || !SERVICE_ROLE) {
          return json({ error: "Server is missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY" }, 500);
        }
        const jobId = await dbInsertJob({
          status: "active",
          file_uri: fileUri,
          file_name: fileName,
          mime_type: mimeType,
          payload,
          model,
        });
        // Keep the worker alive past this HTTP response — the job runs to completion server-side.
        EdgeRuntime.waitUntil(runJob(jobId, fileName, payload, model, key));
        return json({ jobId });
      }

      // 5 — status: read a job's state for the client poll (and relaunch / kill-recovery).
      case "status": {
        const jobId = body.jobId;
        if (typeof jobId !== "string" || !jobId) {
          return json({ error: "status requires a jobId" }, 400);
        }
        if (!SUPABASE_URL || !SERVICE_ROLE) {
          return json({ error: "Server is missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY" }, 500);
        }
        const row = await dbGetJob(jobId);
        if (!row) return json({ error: "job not found" }, 404);
        return json({ status: row.status, result: row.result ?? null, error: row.error ?? null });
      }

      default:
        return json({ error: `Unknown op: ${String(op)}` }, 400);
    }
  } catch (e) {
    // Never leak internals (could include the key in a stack); return a generic message.
    return json({ error: "Proxy request failed" }, 502);
  }
});
