// Lab client that routes through YOUR Supabase `gemini-proxy` Edge Function — exactly like the app, using
// the anon key you already have (no separate Gemini key). Mirrors GeminiService's async job path:
//   start (proxy) → upload bytes Mac→Google directly (keyless) → analyze (proxy) → poll status (proxy).
// The big video upload goes straight to Google (the resumable URL is its own credential); only the small
// key-bearing control calls go through your function. Zero dependencies: Node 18+ global fetch only.

import { readFile } from "node:fs/promises";
import { basename } from "node:path";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function cfg() {
  const ref = process.env.SUPABASE_PROJECT_REF;
  const anon = process.env.SUPABASE_ANON_KEY;
  if (!ref || !anon)
    throw new Error("Set SUPABASE_PROJECT_REF and SUPABASE_ANON_KEY (copy the two values from FoodEditor/Secrets.xcconfig).");
  return { url: `https://${ref}.supabase.co/functions/v1/gemini-proxy`, anon };
}

/** POST one op to the proxy with the anon key (same gateway auth the app uses). */
async function proxy(op, fields) {
  const { url, anon } = cfg();
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: anon, Authorization: `Bearer ${anon}` },
    body: JSON.stringify({ op, ...fields }),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`proxy ${op} HTTP ${r.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

/** Open a resumable session via the proxy, then PUT the bytes straight to Google. Returns the file handle. */
export async function uploadVideo(path, mimeType = "video/mp4") {
  const data = await readFile(path);
  const numBytes = data.byteLength;
  const { uploadUrl } = await proxy("start", { numBytes, mimeType, displayName: basename(path) });
  if (!uploadUrl) throw new Error("proxy start returned no uploadUrl");

  const up = await fetch(uploadUrl, {
    method: "POST",
    headers: { "Content-Length": String(numBytes), "X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize" },
    body: data,
  });
  if (!up.ok) throw new Error(`upload bytes HTTP ${up.status}: ${await up.text()}`);
  const file = (await up.json()).file;
  return { uri: file.uri, name: file.name, mimeType: file.mimeType ?? mimeType };
}

/** Upload once; reuse the returned handle across many prompt/model cells. */
export async function prepareVideo(path, mimeType = "video/mp4") {
  return uploadVideo(path, mimeType);
}

function buildPayload({ fileUri, mimeType, prompt, schema, genConfig }) {
  const generationConfig = {
    responseMimeType: "application/json", temperature: 0, topK: 1, seed: 7, maxOutputTokens: 65536, ...genConfig,
  };
  if (schema) generationConfig.responseSchema = schema;
  // fileData only when there's a video — DECIDE is text-only (an empty fileData part is rejected by Google).
  const parts = [...(fileUri ? [{ fileData: { mimeType, fileUri } }] : []), { text: prompt }];
  return { contents: [{ role: "user", parts }], generationConfig };
}

/**
 * Run one generateContent via the proxy's async job (robust for long videos — the worker polls ACTIVE +
 * generates server-side via EdgeRuntime.waitUntil, surviving the request). Returns { text, httpMs }.
 * (The async path only hands back the result text, not finishReason/usage — we infer completeness from the
 * text instead.)
 */
export async function generate({ fileUri, fileName, mimeType, prompt, model, schema = null, genConfig = {}, timeoutMs = 300_000 }) {
  const payload = buildPayload({ fileUri, mimeType, prompt, schema, genConfig });
  const t0 = Date.now();

  // TEXT-ONLY (no video, e.g. DECIDE): use the proxy's SYNCHRONOUS `generate` op (no file-poll). It returns
  // the raw generateContent JSON verbatim, so extract the candidate text here.
  if (!fileUri) {
    const res = await proxy("generate", { payload, model });
    const text = (res?.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");
    if (!text) throw new Error(`generate returned no text — ${JSON.stringify(res).slice(0, 400)}`);
    return { text, httpMs: Date.now() - t0 };
  }

  // VIDEO: the async job (poll files.get → ACTIVE server-side, survives long calls).
  const { jobId } = await proxy("analyze", { fileUri, fileName, mimeType, payload, model });
  if (!jobId) throw new Error("proxy analyze returned no jobId");
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(2500);
    const s = await proxy("status", { jobId });
    if (s.status === "done") return { text: s.result ?? "", httpMs: Date.now() - t0 };
    if (s.status === "failed") throw new Error(`job failed: ${s.error ?? "unknown"}`);
  }
  throw new Error("job didn't finish before timeout");
}
