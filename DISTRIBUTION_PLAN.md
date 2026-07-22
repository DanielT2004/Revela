# Vela — Distribution & Readiness Plan

_Living doc. Consolidates the distribution-readiness audit, the go-to-TestFlight plan,
quota sizing + cost math, and the PERCEIVE accuracy work. Last updated 2026-07-20._

> Goal of this phase: get from "works great for me" → a **public TestFlight link** in the hands
> of 10–20 real food creators (strangers), with per-user identity + quotas so their usage can't
> run up an unbounded Gemini bill, and the compliance surface needed to pass Beta App Review.

---

## 1. Where the app stands today

### ✅ Already done — do NOT rebuild
- **Gemini API key is server-side** in the Supabase `gemini-proxy` (app never sees it).
- **Privacy usage strings** present + well-written in [Info.plist](FoodEditor/App/Info.plist)
  (photo library, add-to-library, mic, speech recognition).
- **App icon** — 1024×1024 in `Assets.xcassets/AppIcon.appiconset`.
- **User-facing error handling** — `GeminiError` has friendly messages (truncation advice,
  404-terminal, timeouts).
- **Job kill-recovery** — async PERCEIVE + style-extraction jobs persist and resume on relaunch.
- **Development Team is set** in the project (`2KU9BC4R2Z` — confirm it's a PAID enrollment).
- **Sign in with Apple is already coded** in [AuthStore.swift](FoodEditor/Services/AuthStore.swift)
  (`signInWithApple(_:)`) — just deliberately hidden in the UI.

### 🔴 The gaps (in severity order)
1. **No backend user identity.** Every request uses the shared anon key. Proxy has a literal
   `TODO (accounts milestone): per-user Supabase Auth + rate-limit / quota here`. This is the
   keystone — quotas are impossible without it.
2. **Zero quota / rate-limiting.** Anyone with the app can run unlimited Gemini jobs on your bill.
3. **No privacy policy or terms** anywhere in-app → App Store guideline 5.1 blocker.
4. **No account deletion** → guideline 5.1.1(v), required once real accounts exist.
5. **ElevenLabs API key ships inside the app binary** (`Secrets.xcconfig` → client). Unlike the
   Gemini key it was never proxied. **Rotate it AND move it behind the proxy** (already exposed on
   your friend's device).
6. **Small compliance bits:**
   - Add `ITSAppUsesNonExemptEncryption = NO` to Info.plist (you only use TLS = exempt; declaring
     it skips a manual question on every upload).
   - `aps-environment: development` flips to `production` automatically when archiving with a
     distribution profile — just verify push works on the first TestFlight build.

---

## 2. The plan — five phases, in dependency order

### Phase 1 — Identity (the keystone, ~3–5 days)
- Wire **Sign in with Apple → Supabase Auth** (native Apple provider). The `signInWithApple(_:)`
  handler already exists — make it exchange the Apple credential for a Supabase **session** instead
  of writing local JSON.
- **Send the user's JWT instead of the anon key** in [GeminiService.swift](FoodEditor/Services/GeminiService.swift)
  (currently `Bearer <anonKey>`), so the proxy knows who's calling.
- **Add `user_id` to the jobs table** (new migration) + RLS so users only see their own jobs.
- **Keep guest mode, but gate the first Gemini analysis behind sign-in** (the moment they're
  invested; friction there is acceptable and is what makes quotas enforceable).
- ⚠️ External dependency: paid **Apple Developer Program** enrollment ($99/yr, ~1–2 day approval).
  TestFlight requires it. Kick this off first if not already done.

### Phase 2 — Quotas & cost tracking (~2–3 days, needs Phase 1)
- New **`usage` table**: `user_id, month, edits_used, style_videos_used`; add per-job token columns
  (`prompt_tokens, output_tokens`) to `jobs` — the proxy **already receives** `usageMetadata` from
  Google and logs it to console; **persist it** instead of dropping it.
- **Enforce in the proxy**: check the counter before creating a job; over quota → **429** with a
  clear body.
- **Client**: add `GeminiError.quotaExceeded` + a paywall-shaped screen ("You've used your 3 free
  edits this month"). Add a **"join waitlist for unlimited"** tap so you *measure demand to pay*
  before billing exists.
- **Abuse guards for everyone** (independent of tier): max ~2 concurrent jobs + a daily cap
  (e.g. 10 edits/day) so one runaway user or a leaked link can't spike the bill overnight.

### Phase 3 — Quota sizing (numbers below in §3)

### Phase 4 — Legal & App Store compliance (~2 days, parallelizable)
- **Privacy policy + terms** hosted on a simple page (GitHub Pages / Notion fine now; App Store
  Connect needs a URL). **Must clearly disclose: user videos are uploaded to Google (Gemini) for
  analysis.** This is also your App Privacy "nutrition label": user content (video, audio)
  collected, linked to identity, used for app functionality. Vagueness here = classic rejection.
- **Account deletion**: "Delete account" row in ProfileView → edge function that deletes the auth
  user + their jobs/usage rows.
- **ElevenLabs key**: rotate + add a tiny proxy endpoint (same pattern as gemini-proxy).
- Add `ITSAppUsesNonExemptEncryption = NO` to Info.plist.

### Phase 5 — TestFlight mechanics (~1 day once above lands)
1. Create app record in App Store Connect (bundle `com.vela.foodeditor`, name "Vela" — check name
   availability now).
2. Archive in Xcode → upload. First external build triggers **Beta App Review** (~1 day) — checks
   the privacy policy URL + video-upload disclosure (hence Phase 4 first).
3. Internal testers (you + friend) get builds instantly, no review — start there while review runs.
4. Generate the **public TestFlight link** for creator DMs; cap testers low (50) so quota math holds.
5. Cadence: keep `1.0`, bump build number per upload; TestFlight builds expire in 90 days — ship
   at least monthly.

**Sequencing:** Phase 1 → 2 are sequential; 3–4 parallel; 5 last. ~2 weeks focused work. Paid
enrollment approval is the only external dependency — start it today.

**Deliberately NOT in this plan:** StoreKit/billing. Don't build payments before strangers retain.
The quota screen + waitlist button gets the demand signal without 2 weeks of subscription plumbing.
Billing = Phase 6, the day someone hits the paywall and taps the button.

---

## 3. Quota sizing + cost math

### Cost per operation (estimates from current token budgets — replace with real logged usage)
- **One edit** = 1 PERCEIVE (flash, video) + 1 DECIDE (pro, text) ≈ **$0.25–0.40**
  - PERCEIVE flash @ 1 fps: ~$0.05–0.10
  - DECIDE pro: ~$0.15–0.30
- **One style learn** (1× flash per finished TikTok + 1 pro consolidation for N≥2) ≈
  **$0.30–0.50 for a 3-video learn**

### Recommended tiers
| Tier | Quota | Worst-case COGS | Logic |
|---|---|---|---|
| **Free** | 1 style learn (≤3 videos) + **3 edits/month** | ~$1.70 first mo, ~$1.20/mo after | Enough to feel the magic; deliberately **below** a real creator's 2–3-posts/week cadence — the cadence is what converts |
| **Paid (~$14.99/mo, later)** | **30 edits/mo** + style refinements | ~$12 if maxed, realistically $3–6 | Covers daily posting; cap protects against archive batch-processors |
| **Beta testers (now)** | 15–20 edits/mo, hand-flagged | a few $/user | Never blocks testing; 50 testers stay under ~$100/mo total |

**Strategic note:** free = **3, not 10**. Activation needs one style learn + 1–2 real edits;
beyond that you subsidize their posting schedule and kill the reason to pay. If testers churn
before their 3rd edit, that's a product problem, not a quota problem.

---

## 4. PERCEIVE accuracy — separate track (quality of the Flash "watch the video" call)

**The core finding:** decoding is already deterministic (`temperature: 0, topK: 1, seed: 7` in
[GeminiService.swift:533](FoodEditor/Services/GeminiService.swift#L533)), and the transcript with
word timings + clip starts is already prepended. So mistakes are **not** sampling noise.
**The big miss: nothing sets `mediaResolution` or `fps`, so Gemini watches the proxy at the default
~1 frame/second** — a 3-min video = ~180 stills. Sub-second food shots contribute 0–1 frames →
this is the root of the documented segmentation instability (16–46 shots on identical input).

**"Just use Pro" is only half right:** Pro sees the *same 180 frames*. It fixes reasoning errors
(mislabels), not ingestion misses (missed/wrong boundaries). Split the failure modes:
- Missed shots / wrong boundaries / unstable segmentation → **ingestion** problem → fix with fps.
- Mislabels / misreads (waffle-vs-fries class) → **reasoning** problem → Pro + more thinking help.
- Timestamp drift → transcript anchors already fight this; higher fps tightens the visual side.

### Levers, in order to pull them
1. **Raise sampled frame rate** (cheapest, likely biggest win). Pass `videoMetadata.fps` (e.g. 3–5)
   on the file part. 5 fps on a 3-min video ≈ 230k input tokens ≈ **~$0.07 input on Flash** (vs
   ~$0.015 @ 1 fps). 5× the frames seen for a nickel.
2. **A/B in promptlab: flash vs pro × 1 fps vs 5 fps** = 2×2 on 3 fixtures = **~12 calls (~$1–2)**.
   Prediction: flash@5fps fixes most boundary/miss errors; pro@5fps is the quality ceiling — then
   decide if Pro's delta justifies the cost.
3. **Raise PERCEIVE thinking budget** (currently 8,192; try 16–24k) before paying for Pro — often
   closes much of the gap to Pro cheaply. Add as a 5th eval column.
4. **Structural fix (biggest ceiling, more work): stop asking the model to segment.** The deferred
   "deterministic clip-boundary fix" — on-device shot detection (AVFoundation frame-differencing)
   within known clip bounds, then hand Gemini a **fixed** shot list to only describe/label. Kills
   segmentation variance by construction. Build this if instability persists after fps + model tuning.
5. **If fine mislabels persist:** add `mediaResolution: high` (more visual tokens per frame) — the
   lever for "can't tell fries from a waffle at token resolution".

### Cost reality
Flash@5fps adds ~$0.05/edit. Pro@1fps adds ~$0.15–0.30. Pro@5fps ≈ ~$0.60–0.90 — eats real margin
at a 30-edit tier. Exhaust the Flash levers first; let the eval prove whether Pro earns its cost.

⚠️ **Watch:** higher fps = more input tokens AND more output detail → keep an eye on the 65k output
cap for long proxies.

**Standing rule:** no proxy/Gemini calls fired without Daniel's OK (see memory). Wiring the `fps`
param + eval matrix is code-only; Daniel runs the ~12–15 calls and we read results together.

---

## 5. Compliance checklist (App Store / TestFlight)

- [ ] Paid Apple Developer Program enrollment confirmed
- [ ] Sign in with Apple → Supabase Auth wired
- [ ] JWT sent to proxy instead of anon key
- [ ] `user_id` on jobs table + RLS
- [ ] `usage` table + per-job token persistence
- [ ] Proxy quota enforcement (429 over-quota) + concurrency/daily abuse caps
- [ ] `GeminiError.quotaExceeded` + paywall/waitlist screen
- [ ] Privacy policy URL (discloses video → Google upload)
- [ ] Terms of service URL
- [ ] Account deletion (UI + server purge endpoint)
- [ ] ElevenLabs key rotated + proxied (out of binary)
- [ ] `ITSAppUsesNonExemptEncryption = NO` in Info.plist
- [ ] Verify push works on first production-entitlement TestFlight build
- [ ] App Store Connect record created (name availability checked)
- [ ] App Privacy "nutrition label" filled (user content, linked to identity)
