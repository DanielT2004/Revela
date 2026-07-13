# Vela TestFlight Beta Readiness — Solo Dev → 5-15 Friends

## (1) TestFlight Launch Checklist

### Signing & Capabilities
- **Team + bundle ID**: Confirm your paid Apple Developer account team is set under *Signing & Capabilities* for the `FoodEditor` target. Your bundle ID (the same one set in `APNS_BUNDLE_ID` on the Supabase secret) must match exactly, or APNs tokens will silently fail.
- **Push Notifications capability**: Must be added in Xcode → Signing & Capabilities → `+` → Push Notifications. Without it, `UIApplication.shared.registerForRemoteNotifications()` (called in `NotificationService.requestAuthorization`) returns an error, `deviceTokenHex` stays nil forever, and closed-app APNs pushes never fire. The server silently skips push when the token is nil — which is fine for TestFlight if you accept that; but confirm intentionally.
- **Background Modes**: If not already enabled, check *Background fetch* and *Remote notifications* under Background Modes. The app uses `BackgroundActivity.run` with `UIApplication.beginBackgroundTask` for the upload window; the compression step explicitly tells the user to stay in the app, so Background Processing mode is not required but Remote Notifications is needed for APNs wake.
- **Photos / `NSPhotoLibraryUsageDescription`**: Must be in `Info.plist`. The picker (`PHPickerViewController`) fails silently without it on a fresh device. Confirm the string is present — search `Info.plist` for `NSPhotoLibraryUsageDescription`.
- **`NSUserNotificationsUsageDescription`** (or the correct key `NSUserNotificationUsageDescription`): Needed for the `UNUserNotificationCenter` prompt. Confirm in `Info.plist`; TestFlight reviewers check this.
- **`SUPABASE_PROJECT_REF` / `SUPABASE_ANON_KEY`**: Read from `Info.plist` via `Bundle.main`. Verify `Secrets.xcconfig` is configured and included in the build scheme — a missing anon key gives every tester `GeminiError.missingConfig` immediately.
- **Archive scheme**: Build with the `FoodEditor` scheme → Generic iOS Device → Product → Archive. Do NOT pass `CODE_SIGNING_ALLOWED=NO` to an archive (that flag is only for CI build-checks per CLAUDE.md).
- **`FeatureFlags.twoCallPipeline`**: The flag defaults `true` in `#if DEBUG` and `false` in `#else` (release). A TestFlight archive is a release build, so the two-call PERCEIVE→DECIDE pipeline ships **off** by default. Decide if that is the intended TestFlight experience; if you want testers on the new pipeline, flip the default or set the `UserDefaults` key in the shipped build.
- **Supabase migration `0004_jobs_notify_kind.sql`**: The `notify_kind` column must exist in the `jobs` table before the first tester runs a style analysis. If the migration is not yet applied, the `analyze` insert will fail (PostgreSQL will reject the field). Apply it via `supabase db push` or the Supabase dashboard before submitting.
- **APNs `.p8` secrets on Supabase**: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_AUTH_KEY` must be set as Supabase Edge Function secrets. Missing any one of them causes the proxy to silently skip push (the `sendApnsPush` guard at line 177 of `index.ts`). The job still completes; users just get no notification when the app is closed.
- **TestFlight `apnsEnv`**: `NotificationService` sends `apnsEnv` based on whether the token is sandbox or production. TestFlight builds use the **production** APNs environment (not sandbox), so `APNS_AUTH_KEY` must be a production-capable key. If you are currently using sandbox only, pushes will fail silently for TestFlight users.

### What Breaks When the Tester's Device Differs
- **iOS version**: Code uses `exportAsynchronously` (iOS 17+) — anyone on iOS 16 or below crashes on export. Declare `IPHONEOS_DEPLOYMENT_TARGET` = 17.0 or add a guard.
- **iOS 26.1/26.2 known bug**: `preselectedAssetIdentifiers` no-ops on iOS 26 (noted in CLAUDE.md). Testers on iOS 26 will not see their prior selections pre-highlighted in the picker, which is confusing but not a crash.
- **Disk space**: The proxy compression produces a temporary 720p video per clip. On low-storage devices, `AVAssetExportSession` silently fails. There is no explicit disk-space pre-check in `VideoPreprocessor`.
- **No physical camera roll videos**: Simulator testers cannot use the real flow — all analysis requires picking an actual video.
- **Different video codecs** (HEVC from iPhone 12+ vs H.264): `VideoPreprocessor.mergeAndCompress` re-encodes to H.264/720p so Gemini handles it uniformly; this is already covered. But extremely long/corrupt HEVC files can cause `insertTimeRange` throws (see KNOWN_ISSUES item 5: `transcribe-timebase-divergence`).

---

## (2) Multi-User Risks

### The System Assumes a Single User Throughout
- **`AuthStore`**: Auth is entirely local — `AuthMethod.guest` / `phoneStub` with no server identity. There is no user ID attached to the `jobs` table rows (`0001_jobs.sql` schema, not shown but described in the proxy). Any user with the Supabase anon key can call `status` with any `jobId` UUID and read another user's raw Gemini result. With 5-15 friends this is low practical risk but is a real data-exposure issue.
- **`AnalysisJobStore` / `StyleJobStore`**: Job IDs are persisted per-device in Application Support. Two users on different devices do not interfere. The risk is the anon key shipped in `Secrets.xcconfig` (injected into `Info.plist`) — any tester can extract it and call the proxy directly with no auth beyond the Supabase JWT the anon key grants. The proxy comment (`// TODO (accounts milestone): per-user Supabase Auth + rate-limit / quota here`) acknowledges this.
- **`NotificationService.deviceTokenHex`**: Stored in `UserDefaults.standard` under `"apnsDeviceToken"`. One token per device — no cross-user bleed. But if the token is stale (user reinstalled), APNs returns 410 and the proxy logs a warning without purging it (no cleanup path in `dbUpdateJob`).
- **`TemplateService` / `TemplateStore`**: Templates and the `active` template are stored locally per device. No cross-user contamination.
- **Jobs table**: No RLS per-user filtering — service-role only. The `dbGetJob` query filters by `id=eq.${id}`, so guessing another UUID leaks the result text. Low risk with friends, real risk at any scale.

### Gemini Cost Estimate — Worst Case, 10 Friends × 5 Analyses

| Call | Model | Approximate cost |
|---|---|---|
| PERCEIVE (async, `analyze` op, Flash) | gemini-2.5-flash | ~\$0.01–\$0.02/run (video token pricing; ~5-min video) |
| DECIDE (sync, `generate` op, Pro) | gemini-2.5-pro | ~\$0.03/run (noted in MEMORY.md) |
| Style extraction (Flash) | gemini-2.5-flash | ~\$0.01–\$0.02/run |

A full edit-pipeline run (PERCEIVE + DECIDE) ≈ \$0.04–\$0.05. If `twoCallPipeline` is off (the release default), it is one Flash call only ≈ \$0.01–\$0.02.

**10 friends × 5 edit runs × \$0.05 = \$2.50/day worst case** (two-call pipeline on). Style analyses add perhaps \$0.01–0.02 each. Total ceiling with style: ~\$3–5/day. This is entirely manageable.

**What stops a runaway?** Nothing automatic. There is no per-user quota, no daily cap, no circuit breaker in the proxy. A bug causing a retry loop (e.g. an idempotency failure on `analyze` per KNOWN_ISSUES item 3) could create duplicate jobs. The `pg_cron` reaper cleans orphaned rows after 4 minutes but does not kill spend. At 5-15 friends the financial risk is low; set a Google Cloud budget alert on your Gemini API key as a backstop.

---

## (3) Crash & Feedback Loop

### What You Get For Free
- **TestFlight crash reports**: Crashes are automatically symbolicated and appear in App Store Connect → TestFlight → Crashes within ~24h. You need the dSYM (Xcode archives it; submit it with the build or upload manually via `xcrun altool`).
- **Xcode Organizer**: Connects to the live crash feed if testers have diagnostics sharing enabled on their device.
- **Supabase Edge Function logs**: `console.log` / `console.error` in `index.ts` appear in the Supabase dashboard under Functions → Logs. Every `[runJob]` step is logged, so server-side failures are visible without any client instrumentation.

### What to Add Before Beta

**Minimal in-app feedback affordance** (strongly recommended): Add a "Send feedback" button on the Home screen or via a long-press. The simplest implementation: `MFMailComposeViewController` pre-addressed to your email with the subject line auto-set to "Vela Beta Feedback." This costs ~40 lines of SwiftUI + UIKit. Without it, testers have no low-friction way to report "it got stuck on uploading."

**Log shipping to Supabase** (optional but high-value): Each `Log.*` category writes to `os_log` in `Log.swift`. On a tester device these vanish. Consider writing the last N log lines to a rolling `UserDefaults` string and including them in the feedback email body. No third-party SDK required.

**Structured failure states to surface**: The two most likely failure modes to go invisible:
1. `GeminiError.missingConfig` — shown to the user but not reported anywhere. Add a `Log.app` call + include in feedback.
2. `phase = .failed(message)` in `AnalysisCoordinator` / `StyleAnalysisCoordinator` — the user sees an error string in the UI; the raw string is logged with `Log.gemini`. Make sure the ProcessingView / AnalyzingStepView copies that string verbatim so the tester can screenshot it.

**TestFlight tester notes**: Write a short "known issues" note in the TestFlight What to Test field. Flag: (a) stay in the app during compression, (b) iOS 26 picker pre-selection doesn't work, (c) how to force-retry if it gets stuck.

---

## (4) Five Things to Fix Before Friends Touch It vs. What Can Wait

### Fix Before Launch

**1. Apply migration `0004_jobs_notify_kind.sql` to production.**
The `analyze` insert sends `notify_kind` in the row. If the column doesn't exist, the first style-analysis job any tester runs returns a 500 from PostgREST and fails immediately. Run `supabase db push` against the linked production project now.

**2. Verify `NSPhotoLibraryUsageDescription` and `NSUserNotificationsUsageDescription` are in `Info.plist`.**
Missing either one crashes (Photos) or silently breaks (notifications) on a fresh device. These are the two most common TestFlight rejection and first-run failure causes.

**3. Confirm `apnsEnv` is `"production"` in TestFlight builds.**
`NotificationService` does not currently auto-detect production vs. sandbox — it relies on `apnsEnv` being passed correctly. Check where in the app this string is set and verify it resolves to `"production"` for a release/TestFlight archive. If the server is posting to `api.sandbox.push.apple.com` for TestFlight users, all closed-app pushes silently fail.

**4. Set a Google Cloud budget alert on the Gemini API key.**
No quota gate exists in the proxy. Even at small scale, a runaway retry loop or a misconfiguration could spend freely. A \$10/day alert costs nothing and takes 2 minutes to configure in the Google Cloud console.

**5. Add a one-line "Send Feedback" affordance on the Home screen.**
Without a feedback path you are flying blind. A `mailto:` deep link in a menu or a long-press gesture on the Home screen takes under an hour to add and will pay for itself on the first tester who hits a stuck-uploading state.

### Can Wait

- Per-user auth / RLS on the `jobs` table — low practical risk at 5-15 friends who know each other.
- The `proxy-perceive-no-selfbail` / `proxy-no-retry-5xx` KNOWN_ISSUES items — the reaper covers orphaned rows; occasional transient 503s surface as "Retry" in the UI.
- Idempotency key on `analyze` (KNOWN_ISSUES item 3) — duplicate job on a lost response creates a second paid call but doesn't crash; manageable at small scale.
- Recent-projects persistence — explicitly deferred in CLAUDE.md.
- The iOS 26 PHPicker preselection bug — Apple regression; nothing actionable on your end.