# Vela Dev Audit — 2026-07-08 — Verified Bug Findings

Multi-agent audit of the working tree (style-learning flow + pipeline). Every finding below was adversarially verified against the real source; verdicts included.


## [MEDIUM] Kill-resumed style template that completes off-Home is permanently unreachable (paid result stranded)

**Where:** `FoodEditor/Views/RootView.swift:195`  
**Dimension:** diff-correctness


**What happens:** For a .newTemplate kill-resume, the ONLY passive completion surface is revealTemplateIfSafe(), which fires solely on the .done phase TRANSITION and only when router.screen == .home. If the resumed job finishes while the user is on any other screen (e.g. they cold-launched and immediately tapped 'New video' into .picker/.brief, or are mid-edit), the reveal no-ops and never re-fires — phase is already .done and StyleJobStore was already cleared by resumePipeline. Unlike the edit pipeline (HomeView renders a card from `analysis` and the result persists as a project), HomeView reads only `analysis` — there is no card or list entry for create.coordinator, so the finished template has zero UI surface. The one remaining path is the APNs push tap, but RootView consumes appRoute.pending unconditionally (`routeToTemplateIfSafe(); appRoute.pending = nil`) even when routeToTemplateIfSafe's safe-screen guard no-ops — a tap from .editor/.export/.segments burns the one-shot intent and does nothing. After that, the paid Gemini result lives only in coordinator memory; starting a new create flow (create.startUpload() resets draft) launches a second paid extraction. Recovery exists only in the obscure case of re-picking the exact same video (signature match → start() returns .done and AnalyzingStepView's .task fires onDone).


**Evidence:** RootView.swift:136-138: `.onChange(of: create.coordinator.phase) { _, phase in if phase == .done { revealTemplateIfSafe() } }` — transition-only. RootView.swift:195-200: `private func revealTemplateIfSafe() { guard let t = create.coordinator.template, create.draft == nil else { return }; guard router.screen == .home else { return } ... }`. RootView.swift:127-128 and 144-145: `if pending == .template { routeToTemplateIfSafe(); appRoute.pending = nil }` — pending cleared even when the guard `guard safe.contains(router.screen) else { return }` (line 208) no-ops. HomeView.swift:111 shows a processing card only for `analysis.phase == .running`; nothing reads create.coordinator. Trace: kill mid-learn → relaunch → RootView.task resumes (phase .running) → user taps into .picker → job completes → onChange fires, revealTemplateIfSafe returns (screen != .home) → push tapped from .picker → safe set {home, createSource, createSelect, createAnalyzing} excludes .picker → no-op + pending=nil → template stranded forever.


**Suggested fix:** Re-check for an unrevealed .done template whenever the user returns to .home (e.g. in the router.screen onChange, or render a HomeView card off create.coordinator.phase like the analysis card), and only clear appRoute.pending when the route actually happened (have routeToTemplateIfSafe return Bool).


**Verifier verdict:** UPHELD: Confirmed by tracing RootView.swift. The `.onChange(of: create.coordinator.phase)` at line 136 only fires on the phase transition to `.done`; if the user is not on `.home` at that moment, `revealTemplateIfSafe()` guards on `router.screen == .home` and no-ops — and there is no re-fire mechanism since phase is already `.done`. The push-tap path via `routeToTemplateIfSafe()` is burned unconditionally: line 128 sets `appRoute.pending = nil` regardless of whether `routeToTemplateIfSafe()` actually navigated (the safe-screen guard at line 207 no-ops silently, but `pending` is cleared). The scenePhase `.active` re-check at line 144-145 also clears `pending` the same way. CreateFlow has no persistence; after a kill `create.coordinator.template` is only in memory. A cold-launch → immediate tap into `.picker` (or similar) while a resume is in progress is a plausible beta scenario. Medium severity stands.


## [MEDIUM] Post-kill failure recovery is broken: Retry is a guaranteed dead click (empty clips) and the failure push tap dead-ends

**Where:** `FoodEditor/Views/Onboarding/AnalyzingStepView.swift:163`  
**Dimension:** diff-correctness


**What happens:** When a resumed style job resolves as failed (reaper-failed row, blocked response, or the timeout in the previous finding), phase=.failed and the pending record is cleared. Every retry surface then malfunctions: (1) AnalyzingStepView's error state calls `coordinator.retry(clips: clips)` where clips are `session.clips` (onboarding) or `create.selectedClips` (create flow) — both EMPTY after a kill, so retry() → launch() → run() hits `guard !clips.isEmpty else { phase = .failed("No videos to learn from.") }`: the Retry button can never succeed post-kill, it just swaps the error message. (2) For the .newTemplate origin resumed from RootView, nothing observes .failed at all — the user on Home sees nothing (no card, no notification: resumePipeline's catch doesn't notify). (3) The server failure push says 'Open Vela to try again.' with screen:'template', but routeToTemplateIfSafe has no .failed branch, so the tap opens the app to Home with no error UI and no path to 'try again' other than manually rebuilding the create flow from scratch.


**Evidence:** AnalyzingStepView.swift:163: `Button("Retry") { coordinator.retry(clips: clips) }` with clips injected as `session.clips` (OnboardingView.swift:30) / `create.selectedClips` (RootView.swift:57) — both empty after process death. StyleAnalysisCoordinator.swift:81: `guard !clips.isEmpty else { phase = .failed("No videos to learn from."); return }`. index.ts:239-244 failure push: `isStyle ? "Style analysis hit a snag" : ...`, body `"Open Vela to try again."`, `{ screen: "template" }`; RootView.swift:209-214 routes only .done/.running. Trace: kill mid-learn → server job reaped → relaunch → resume reads 'failed' → clear + .failed → onboarding user lands on error screen where Retry always fails ('← Back' to re-pick is the only working path); create-flow user gets total silence.


**Suggested fix:** Hide/disable Retry when clips.isEmpty (route Back to the picker instead), and surface .failed for the .newTemplate origin (Home card or a routed error state; give routeToTemplateIfSafe a .failed branch that lands on .createSource with a toast).


**Verifier verdict:** UPHELD: Confirmed. AnalyzingStepView line 163 calls `coordinator.retry(clips: clips)` where `clips` is `session.clips` (onboarding) or `create.selectedClips` (create flow) — both are in-memory VideoSession state that is empty after process death. StyleAnalysisCoordinator.run() line 81 guards `guard !clips.isEmpty else { phase = .failed(...) }`, so the Retry button post-kill always re-fails immediately. For the `.newTemplate` origin resumed from RootView there is no `.failed` observation at all — no card, no notification, total silence. The failure push tap routes to `screen: 'template'` but `routeToTemplateIfSafe()` has no `.failed` branch. The only real recovery path for an onboarding user is '← Back' to re-pick. Medium severity: a failed resume is uncommon in beta, but when it happens the user has no indication and no path forward except manually restarting the flow.


## [MEDIUM] Learned (paid) style template is permanently lost if its .done lands off-Home or the app is killed during review — StyleJobStore is cleared before anything durable exists

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:155`  
**Dimension:** beta-failure-modes


**What happens:** The kill-recovery record (StyleJobStore) is cleared the instant phase flips to .done, but the template only becomes durable when the user taps Save in TemplateEditorView (templates.save). Between those two points the ONLY copy is in-memory. Three concrete beta paths lose it: (1) Kill-resume completes while the user is NOT on .home (e.g. they opened the app and immediately tapped New video → .picker, or are browsing .templateLibrary): RootView.revealTemplateIfSafe guards `router.screen == .home` and .onChange never re-fires, so the finished template is unreachable except via the push notification — if that push was dismissed (or never sent, see the token-race finding), the result is gone; a fresh create flow resets draft and re-pays. (2) User reaches .createReview (or onboarding step 4), backgrounds the app to check messages, iOS evicts it → relaunch lands on Home (or onboarding step 0) with draft/analyzedTemplate gone, StyleJobStore already empty, so resumeIfPending no-ops — the whole analysis must be redone and re-paid. (3) For onboarding this restarts the ENTIRE onboarding at Welcome. The edit pipeline's analog is recoverable from Home's processing card/project list; the style flow has no equivalent surface.


**Evidence:** StyleAnalysisCoordinator.run (live) and resumePipeline both do:
```
phase = .done
StyleJobStore.clear()   // template built — drop the kill-recovery record + durable poster
```
RootView.swift:195-199:
```
private func revealTemplateIfSafe() {
    guard let t = create.coordinator.template, create.draft == nil else { return }
    guard router.screen == .home else { return }   // off-Home ⇒ silent no-op, never re-fires
```
Trace (path 2): create learn → kill mid-poll → relaunch → RootView.task resumeIfPending → job done → revealTemplateIfSafe (on .home) → .createReview → user backgrounds in TemplateEditorView → iOS kills app → relaunch: StyleJobStore.load() == nil (cleared at .done), create.draft is @Observable in-memory state re-created fresh → template gone; jobs.result still sits in the server row but the client discarded the only jobId reference.


**Suggested fix:** Don't clear StyleJobStore at phase .done — clear it in templates.save()/onSave (and on genuine job failure). Alternatively persist the built template (or at least the jobId) to disk at .done so relaunch can re-offer it, and have HomeView show a 'style ready' card mirroring the edit pipeline's processing card.


**Verifier verdict:** UPHELD: The core claim is confirmed by the code. `StyleJobStore.clear()` is called at line 155 of StyleAnalysisCoordinator.swift the moment `phase = .done`, before the user ever taps Save in TemplateEditorView. Path 2 (kill during review) is a genuine data-loss path: if the app is evicted while the user is on `.createReview` or the onboarding step 4, `create.draft` and `analyzedTemplate` are in-memory @Observable state — gone on next launch — and `StyleJobStore.load()` returns nil because it was already cleared. The user must redo the analysis and pay again. However, the finding overstates severity for path 1 (off-Home during live run): `routeToTemplateIfSafe()` (RootView line 205-215) is triggered by both the notification tap and by `.onChange(of: scenePhase)` → `.active`, and checks `create.coordinator.phase == .done` AND `create.coordinator.template != nil` — the coordinator lives in memory so if the process has NOT been killed, the template is still reachable via push tap even if the user was off `.home` when `.done` fired. The dangerous window is only kill-during-review (path 2) and onboarding step 4 kill. Both are real for a beta friend who backgrounds to check messages. Severity downgraded from high to medium because (a) the kill-during-review window is short (the review screen is interactive, not a waiting screen), and (b) the onboarding case is more impactful but the user has been staring at the app for the whole learn so backgrounding is less common there.


## [MEDIUM] start() silently no-ops on .running without a signature check — a redone create-flow learn shows the NEW video's thumbnails but delivers the OLD video's template

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:47`  
**Dimension:** beta-failure-modes


**What happens:** A kill-resumed create-flow learn is completely invisible (no Home card, no toast — HomeView only renders a card for `analysis`, the edit coordinator). A beta user who killed the app mid-learn relaunches, sees nothing happening, assumes the learn was lost, and redoes it: templateLibrary → createSource → picks a DIFFERENT video B → Analyze. AnalyzingStepView.task calls create.coordinator.start(clips: [B]), but the shared coordinator is already .running the resumed job for video A, and the .running branch returns without comparing clip signatures. The screen renders video B's thumbnails and 'Learning a different side of your edits' while actually polling video A's job; onDone hands back video A's StyleProfile, which is saved as video B's template. Silent wrong result, no error anywhere. (The edit pipeline has the same .running no-op but its running state is visible on Home, making the double-start far less likely.)


**Evidence:** StyleAnalysisCoordinator.start:
```
switch phase {
case .running:                                   return   // no signature comparison
```
Trace: (1) create-learn video A → StyleJobStore.save → app killed. (2) Relaunch → RootView.task → create.coordinator.resumeIfPending() → phase .running, nothing on screen indicates it. (3) User re-picks video B → router.go(.createAnalyzing) → AnalyzingStepView.task → start(clips:[B]) → `case .running: return`. (4) AnalyzingStepView collage shows clips = create.selectedClips (video B) while coordinator.progress/label track job A. (5) resumePipeline → template built from job A's profile → onDone(t) → create.draft = A-template → .createReview presents it as the new template for B.


**Suggested fix:** In start(), when phase == .running and AnalysisCoordinator.signature(for: clips) != self.signature, cancel the in-flight task (or refuse with a visible message) instead of silently returning; and/or surface the resumed run with a Home card so users don't redo it.


**Verifier verdict:** UPHELD: Confirmed from StyleAnalysisCoordinator.swift line 46-47: `case .running: return` with no clip-signature comparison. The kill-resume path makes this reachable: resumed coordinator is `.running` with no visible UI card on Home (HomeView renders a card only for `analysis`, the edit coordinator, not `create.coordinator`). A beta user who doesn't know a resume is in flight, re-picks a different video B, and taps Analyze hits `AnalyzingStepView.task` → `coordinator.start(clips:[B])` → no-op. The view renders B's thumbnails (from its `clips` parameter), while the coordinator polls job A. `onDone` fires with `coordinator.template` built from A's StyleProfile, which is then saved as B's template. Silent wrong result — no error, no indication. This is a real correctness bug. It's medium rather than high because it requires the specific combination of: (1) a kill mid-learn, (2) the user not noticing the resume in flight, and (3) deliberately picking a different video. In practice most beta users who kill-resume will be told by the push to 'open Vela to review your style', which routes to `.createAnalyzing` showing the ongoing analysis — making the double-start scenario less likely but not impossible.


## [MEDIUM] Retry after any kill-resume failure is a guaranteed dead click: it retries with an empty clips array → 'No videos to learn from.'

**Where:** `FoodEditor/Views/Onboarding/AnalyzingStepView.swift:163`  
**Dimension:** beta-failure-modes


**What happens:** After an app kill, the picked clips are gone (temp files + in-memory session state). Kill-recovery re-attaches by jobId only. If the resumed job resolves as failed (Gemini 5xx written as permanent failure, reaper-evicted worker, 300s poll timeout), AnalyzingStepView shows the error state whose Retry button calls coordinator.retry(clips:) with the now-empty clips array (session.clips for onboarding, create.selectedClips for the create flow). retry() clears StyleJobStore and relaunches → run() immediately fails its !clips.isEmpty guard → the error text just changes to 'No videos to learn from.' Every tap of Retry fails forever. This is also the landing experience of the failure push: 'Style analysis hit a snag — Open Vela to try again' → tap → routeToTemplateIfSafe sees phase .running (resume in flight) → .createAnalyzing → resume resolves failed → error state with the dead Retry. A beta friend will tap Retry (as the push told them to), see a nonsense error, and be stuck; the actual recovery ('← Back' to re-pick) is not signposted.


**Evidence:** AnalyzingStepView.errorState:
```
Button("Retry") { coordinator.retry(clips: clips) }
```
with `clips` = session.clips / create.selectedClips == [] post-kill.
StyleAnalysisCoordinator.retry → launch → run:
```
guard !clips.isEmpty else { phase = .failed("No videos to learn from."); return }
```
Trace: style job started → app killed → job fails server-side (fail() always pushes) → user taps push → cold launch → resumeIfPending (.running) → routeToTemplateIfSafe → .createAnalyzing → resumePipeline catch → .failed(msg) → errorState → Retry → .failed("No videos to learn from.") → Retry → same, forever.


**Suggested fix:** When clips.isEmpty (resume context), hide Retry or replace it with 'Pick the video again' that routes back to the picker step; alternatively persist the clip's PHAsset identifier in PendingStyleJob so Retry can re-fetch the source.


**Verifier verdict:** UPHELD: Confirmed end-to-end. AnalyzingStepView.errorState line 163: `Button("Retry") { coordinator.retry(clips: clips) }` where `clips` is the view's parameter — `session.clips` for onboarding (OnboardingView line 29) and `create.selectedClips` for the create flow (RootView line 57). After an app kill, both are empty in-memory state. `retry()` calls `launch()` then `run()`, which hits `guard !clips.isEmpty else { phase = .failed("No videos to learn from."); return }` at line 81. Every subsequent Retry tap produces the same nonsense error. The `← Back` button is present and functional, but it's not signposted as the recovery action — the UX implies Retry should work. This is particularly bad on the failure push tap path: the notification body says 'Open Vela to try again' → user taps → routed to `.createAnalyzing` → resume resolves failed → error screen → Retry loops forever. A beta friend following the push's instruction will be stuck. Severity is medium (not high) because the workaround (Back → re-pick) is one tap away and does work, and the failure push scenario requires a server-side job failure which is uncommon.


## [MEDIUM] Create-flow kill-resume failure is 100% silent: no error UI, no notification, record cleared — the learn just evaporates

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:237`  
**Dimension:** beta-failure-modes


**What happens:** When a killed create-flow style job is resumed from RootView (user lands on Home, resume runs headless) and the poll resolves as failed — or times out after 300s while the job is genuinely still running server-side — resumePipeline's catch clears StyleJobStore and sets phase .failed with NO local notification (unlike AnalysisCoordinator's resume failure, which posts 'Analysis hit a snag') and no screen observing .failed (RootView only watches for .done; HomeView renders no card for create.coordinator). Unless the user happens to be sitting on .createAnalyzing, nothing anywhere tells them it failed. If they dismissed (or never received) the server failure push, the flow dead-ends invisibly: they wait for a 'style is ready' push that will never come. Worse, the timeout branch clears the pending record even though the server job may still complete afterwards — the later success push's tap then hits routeToTemplateIfSafe with phase == .failed (neither .done nor .running) and no-ops on Home with zero feedback.


**Evidence:** resumePipeline catch:
```
} catch {
    if Task.isCancelled { return }
    Log.gemini("Style resume error: ...")
    StyleJobStore.clear()
    phase = .failed(error.localizedDescription)   // no notify(), nothing observes .failed
}
```
Contrast run()'s catch which at least posts a local 'Style analysis hit a snag' when tokenless. RootView has `.onChange(of: create.coordinator.phase) { if phase == .done ... }` only; grep confirms no view outside AnalyzingStepView reads create.coordinator.phase. Trace: kill mid-learn → relaunch to Home → resumeIfPending → awaitJobResult throws (job failed / 300s timeout) → clear + .failed → user on Home sees nothing, ever.


**Suggested fix:** In resumePipeline's catch, post the same local failure notification run() does (and don't gate it on deviceTokenHex when no server job failure push is guaranteed), and/or surface .failed on Home; on GeminiError.timedOut, keep the StyleJobStore record instead of clearing so a later relaunch can still re-attach.


**Verifier verdict:** UPHELD: Confirmed from resumePipeline catch block (StyleAnalysisCoordinator.swift lines 234-239): on any error, it calls `StyleJobStore.clear()`, sets `phase = .failed(...)`, and returns — no `notify()` call, no local notification posted regardless of token state. RootView's `.onChange(of: create.coordinator.phase)` only checks `if phase == .done` (line 136-137), so `.failed` is invisible to RootView. No view outside `AnalyzingStepView` observes `create.coordinator.phase`, and if the user is on `.home` during the background resume, they are never on `AnalyzingStepView`. The user's only signal would be the server failure push — but if that was dismissed, never received (token race), or if the failure was a 300s poll timeout (where the server job may still be succeeding), the user is left waiting for a completion push that will never come, with the record already cleared so the next tap into `.createAnalyzing` starts fresh. The 300s timeout case is particularly bad: the server job may complete afterward and push success, but `routeToTemplateIfSafe()` then finds `phase == .failed` (not `.done` or `.running`) and no-ops. Contrast with the edit pipeline's `AnalysisCoordinator.resumeIfPending` which posts a 'Analysis hit a snag' local notification on resume failure. Medium severity because the server failure push is the primary signal and works in the common case.


## [MEDIUM] Style 'Analyzing' screen has no cancel/back while running; with waitsForConnectivity a network drop mid-upload freezes onboarding step 3 for up to 10 minutes

**Where:** `FoodEditor/Views/Onboarding/AnalyzingStepView.swift:46`  
**Dimension:** beta-failure-modes


**What happens:** AnalyzingStepView's running state (analyzingState) renders only the collage/narration/progress bar — onBack is exposed exclusively in errorState. GeminiService's URLSession is configured with waitsForConnectivity = true and timeoutIntervalForResource = 600, so if a first-run user hits onboarding step 3 (or .createAnalyzing) with no/flaky connectivity, the proxy `start` call and the phone→Google upload don't fail fast — they silently wait for connectivity for up to 600 seconds. The user stares at 'VELA IS WATCHING' with a stalled progress bar for up to 10 minutes with no cancel, no back, no 'check your connection' message. The only escape is force-killing the app, and since the failure is pre-job (nothing persisted in StyleJobStore yet), an onboarding user relaunches into step 0 and starts over. This is the exact 'spinner with no error UI' dead end, on the very first screen a beta friend meets after picking their video.


**Evidence:** GeminiService.swift:88-94:
```
cfg.timeoutIntervalForRequest = 120
cfg.timeoutIntervalForResource = 600   // video upload + a slow analysis can run long
cfg.waitsForConnectivity = true
```
AnalyzingStepView.analyzingState contains no Button/BackChevronButton; only errorState has `Button("← Back", action: onBack)`. Trace: airplane-mode/dead-zone user finishes ConnectStepView → step 3 → run() → compress succeeds offline → label 'Uploading your video' → upload(at:) → session.data(for: start-op) waits for connectivity → progress frozen ~0.3 for up to 600s → only then throws → errorState finally appears.


**Suggested fix:** Add a back/cancel affordance to analyzingState (cancel the task, return to the Connect/select step), and/or shorten the pre-job network budget (e.g. a 30-60s per-request timeout for the proxy control calls) so a dead connection surfaces the error state quickly.


**Verifier verdict:** UPHELD: Both claims confirmed. AnalyzingStepView's `analyzingState` (lines 46-82) contains no Back button, cancel button, or any escape mechanism — `onBack` is only wired in `errorState` (line 161). GeminiService.swift lines 90-93 confirm `timeoutIntervalForResource = 600` and `waitsForConnectivity = true`. The combined effect: a first-run beta user on spotty LTE finishes step 2 (video picked), proceeds to step 3, compression completes locally (pure AVFoundation, works offline), then the upload call waits for connectivity for up to 600 seconds. The progress bar stalls at ~0.3 ('Uploading your video') with no connectivity message and no way out except force-quitting. Since this is pre-job (nothing persisted in StyleJobStore yet), a force-quit resets onboarding to step 0. For a first-ever beta impression this is particularly damaging. The severity is medium rather than high because: (a) most beta testers will be on known-good WiFi, (b) a temporary network dropout (not total loss) will self-recover, and (c) the 600s cap is a worst case for complete connectivity loss.


## [MEDIUM] iCloud-offloaded video pick fails silently and shows no progress: picker appears frozen during download, then returns to the Connect screen with nothing selected and no error

**Where:** `FoodEditor/Services/VideoLibrary.swift:129`  
**Dimension:** beta-failure-modes


**What happens:** First-run beta users commonly have 'Optimize iPhone Storage' on, so their videos are iCloud-offloaded. VideoPicker's delegate calls provider.loadFileRepresentation, which must download the full original; the returned Progress object is discarded, so after tapping 'Add' the PHPicker sheet just sits there frozen (showPicker only flips false inside onPicked, which fires after all downloads finish) — for a multi-hundred-MB video on LTE that is minutes of apparent hang. If the download errors (network blip, low storage), the failure is only logged; onPicked([]) is delivered and both new call sites (ConnectStepView onboarding step 2, CreateSourceView) do `guard !picked.isEmpty else { return }` — the picker closes and the screen shows 'Pick the videos to learn from' as if the user never picked anything. No toast, no alert. The likely beta report: 'I pick my video and nothing happens.'


**Evidence:** VideoLibrary.swift Coordinator:
```
provider.loadFileRepresentation(forTypeIdentifier: movieType) { url, error in
    defer { group.leave() }
    if let error {
        Log.video("Item \(index) load error: ...")
        return                      // silently dropped
    }
```
(the Progress returned by loadFileRepresentation is unused). ConnectStepView.swift:65-69 (new in this diff):
```
VideoPicker(preselectedIdentifiers: [], selectionLimit: 1) { picked in
    showPicker = false
    guard !picked.isEmpty else { return }   // silent no-op on load failure
```
Trace: offloaded video + spotty network → didFinishPicking → download runs (picker still presented, no spinner) → error → byIndex empty → onPicked([]) → guard return → Connect step unchanged, zero feedback.


**Suggested fix:** Hold the returned Progress and show a loading overlay while copies are in flight; when results.count > 0 but the handed-back array is empty/short, surface a ToastView ('Couldn't load that video — check your connection and try again') instead of silently returning.


**Verifier verdict:** UPHELD: Confirmed from VideoLibrary.swift: `loadFileRepresentation` return value (Progress) is not captured and the error path (lines 129-132) silently logs and returns. In `group.notify` (line 153) the empty `ordered` array calls `onPicked([])`. In ConnectStepView.swift line 66-69 and CreateSourceView.swift lines 63-67, the pattern is `showPicker = false; guard !picked.isEmpty else { return }` — so the picker IS dismissed but the clip is not ingested and no error is shown. 'Optimize iPhone Storage' is on by default for Apple accounts with iCloud Photos. A first-run beta user picking an iCloud-offloaded video on a flaky network sees the PHPicker sheet sit there for minutes (system is downloading the asset), then dismisses to a screen that looks exactly like before they picked. The note about the Progress object confirms no download progress is surfaced. This is a real, high-frequency-for-beta-users bug because first-run users commonly have iCloud Photos with offloaded videos. Medium severity (not high) because a retry on WiFi will succeed, and the picker itself does show system-level loading indicators on iOS.


## [MEDIUM] Client-side style parse failure after a successful server job: user gets a SUCCESS push, then the failure is fully silent and unrecoverable

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:166`  
**Dimension:** parsing-robustness


**What happens:** The style job's server worker pushes "Your style is ready ✨" as soon as the model returns non-empty TEXT — it cannot know whether that text parses as a StyleProfileRaw. If StyleProfileRaw.parse then throws on the client (truncated JSON, prose around two brace blocks, etc. — schema is nil so this is the most parse-fragile call in the app), run()'s catch suppresses the local "hit a snag" notification whenever an APNs token exists, on the assumption that "the worker already pushed 'hit a snag'" — but the worker pushed SUCCESS, not failure. resumePipeline's catch posts no notification at all. Both catches also call StyleJobStore.clear(), so re-attach is impossible. Net effect when backgrounded/killed (the flow's advertised mainline — 'close the app, we'll push you'): the user receives a success push, taps it, RootView.routeToTemplateIfSafe() sees phase == .failed and matches neither the .done nor .running branch, consumes the pending route, and nothing happens. Dead end: success push → blank Home, no error, no retry, paid result discarded.


**Evidence:** StyleAnalysisCoordinator.swift:166-179 (run catch): `StyleJobStore.clear(); phase = .failed(...); if NotificationService.shared.deviceTokenHex == nil { notify("Style analysis hit a snag"...) }` — comment: "On a server-job failure the worker already pushed 'hit a snag'" (false for a client-side parse failure of a SUCCEEDED job). resumePipeline catch (lines 234-239) has no notify at all. gemini-proxy/index.ts runJob: success path pushes "Your style is ready ✨" on non-empty text only. RootView.swift routeToTemplateIfSafe(): `if create.coordinator.phase == .done, ... } else if create.coordinator.phase == .running { ... }` — .failed falls through; caller `if pending == .template { routeToTemplateIfSafe(); appRoute.pending = nil }` consumes the tap regardless. Trace: job done server-side → APNs success push → client polls .done, `try StyleProfileRaw.parse(raw)` throws at line 138 (or 218 resumed) → token exists → silence; tap on push → no-op.


**Suggested fix:** In both catches, distinguish 'the server job itself failed' (GeminiError.badRequest from awaitJobResult — server already pushed the snag) from client-side parse/build failures, and post the local "hit a snag" notification for the latter even when a token exists. Give resumePipeline's catch the same notification as run()'s.


**Verifier verdict:** UPHELD: The code path is exactly as traced. The server pushes 'Your style is ready ✨' on non-empty text (not on a successful client parse), so a truncated or prose-wrapped JSON that passes the server but fails StyleProfileRaw.parse() on the client produces a token-muted failure: the catch block at StyleAnalysisCoordinator.swift:168 checks deviceTokenHex != nil and suppresses the local notification, under the false assumption that the server already pushed a failure notice (it pushed success). StyleJobStore.clear() is called in both catch paths, so the job record is gone. In RootView.routeToTemplateIfSafe() (line 209), phase == .failed matches neither the .done nor the .running branch, so the pending route is consumed (appRoute.pending = nil at line 129) without any navigation — a silent dead end from the user's perspective. The three-step scenario (kill → success push → tap → nothing) is exactly the advertised main-line UX for this feature and will reproduce reliably whenever StyleProfileRaw.parse() throws on a live model response. Adjusting from medium to medium because: (a) parse failure requires an actual JSON defect (less likely with temperature=0) and (b) the user can re-run via the create flow; data is not destroyed. But the silent-failure-on-tap is a genuine UX defect the beta will hit.


## [LOW] StyleJobStore cleared at phase=.done, before the template is saved — kill/jetsam during review loses the paid result

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:155`  
**Dimension:** diff-correctness


**What happens:** Both run() and resumePipeline() call StyleJobStore.clear() the moment the template is built (phase=.done), but the template is only persisted when the user taps Save in TemplateEditorView (templates.save via RootView .createReview onSave / OnboardingView.saveAndEnter). Between .done and Save the template exists ONLY in coordinator memory. If the user backgrounds the app on the review screen and iOS jetsams it (routine for a memory-heavy AVFoundation app), the next launch finds no pending record (cleared), no draft, and a fresh .idle coordinator — the paid extraction is gone and the server row's 'done' result is never referenced again. The edit pipeline is deliberately asymmetric here: AnalysisCoordinator.ship() persists the project FIRST and clears AnalysisJobStore last (AnalysisCoordinator.swift:326 comment 'job done + project saved — drop the kill-recovery record'). The style flow clears before anything durable exists. Deferring clear() to the save/cancel handlers would make a kill-during-review recoverable for free: resumeIfPending would re-poll the done job, jobStatus returns .done immediately, and the template is rebuilt from the stored result.


**Evidence:** StyleAnalysisCoordinator.swift:152-155 (run): `template = built; progress = 1.0; phase = .done; StyleJobStore.clear()` and :220-224 (resumePipeline): `template = built; ... phase = .done; StyleJobStore.clear()`. Persistence only happens later at RootView.swift:72-74 `onSave: { if let draft = create.draft { templates.save(draft, poster: ...) ... } }` / OnboardingView.swift:61-62 `templates.save(t, poster: styleCoordinator.posterImage)`. Contrast AnalysisCoordinator.swift:326: clear() runs only after the project is saved. Trace: learn completes → .createReview shown → user backgrounds to answer a text → jetsam → relaunch → StyleJobStore.load() == nil → resumeIfPending no-ops → template unrecoverable despite the jobs row still holding the result.


**Suggested fix:** Move StyleJobStore.clear() out of the .done paths into the review save/cancel handlers (or clear only after templates.save), so a pending record survives until the template is durably persisted; resume of a 'done' job is already cheap (single status poll).


**Verifier verdict:** UPHELD: Confirmed: StyleAnalysisCoordinator.swift line 155 calls `StyleJobStore.clear()` immediately after `phase = .done`, before the user has touched Save in TemplateEditorView. The template lives only in coordinator memory until `templates.save(draft, poster:)` is called at RootView line 73 (or OnboardingView line 62). A jetsam between `.done` and Save would lose the template with no recovery path. The design asymmetry with AnalysisCoordinator (which clears only after the project is saved) is a real gap. Severity is lowered to low for a friends-beta: the review screen is lightweight (no AVFoundation capture), so jetsam requires deliberate memory pressure while the app is backgrounded mid-review. Possible but not routine.


## [LOW] resumePipeline destroys the pending record on a 300s poll timeout while the job is alive/succeeded server-side — silently

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:237`  
**Dimension:** diff-correctness


**What happens:** resumePipeline's catch treats every non-cancellation error as a genuine job failure: StyleJobStore.clear() + phase=.failed. But GeminiService.awaitJobResult swallows all transient network errors and throws GeminiError.timedOut after 300s — so relaunching the app with no/flaky connectivity (airplane mode, dead zone) for 5 minutes deterministically destroys the kill-recovery record even though the server job finished fine. The success push ('Your style is ready ✨') then arrives once connectivity returns, but tapping it does nothing: routeToTemplateIfSafe only routes for phase .done or .running, and there is no record left to resume. The result is unrecoverable — after a kill the clips are gone, so even Retry can't relaunch it (see separate finding). Compounding it, this failure path posts NO notification at all (unlike run()'s catch which posts a local 'Style analysis hit a snag' when tokenless, and unlike AnalysisCoordinator.resumePipeline:434 which always posts one), and for the .newTemplate origin nothing on screen watches .failed — the resume dies completely silently.


**Evidence:** StyleAnalysisCoordinator.swift:234-239: `} catch { if Task.isCancelled { return }; Log.gemini("Style resume error: ..."); StyleJobStore.clear(); phase = .failed(error.localizedDescription) }` — no notify, clear on any error. GeminiService.swift:286-296: poll loop logs `"Status poll blip (will retry)"` for HTTP/network errors and only exits via `throw GeminiError.timedOut("server job didn't finish in time")` at the 300s deadline — offline polling cannot distinguish 'job failed' from 'no network'. RootView.swift:209-214: routeToTemplateIfSafe has branches only for `.done` and `.running`, so the later success-push tap no-ops. Trace: kill mid-learn → relaunch on airplane mode → resumeIfPending → 300s of swallowed blips → timedOut → clear() + .failed (silent) → wifi returns → push 'Your style is ready' → tap → nothing.


**Suggested fix:** In resumePipeline's catch, only clear StyleJobStore for job-level failures (GeminiError.badRequest, i.e. the row read back 'failed'); keep the record on timeout/transport errors so the next launch retries the poll. Also post the local failure notification like run() does.


**Verifier verdict:** UPHELD: Confirmed. StyleAnalysisCoordinator.resumePipeline lines 234-238: the catch block calls `StyleJobStore.clear()` and sets `phase = .failed` for any non-cancellation error, including `GeminiError.timedOut`. GeminiService.awaitJobResult (line 296) throws `.timedOut` after 300s of swallowed transient errors — so launching on airplane mode for 5 minutes after a kill guarantees this path. Unlike run()'s catch (line 175-178), resumePipeline's catch posts no local notification, making it completely silent. The later APNs success push (once connectivity returns) taps into a no-op because `routeToTemplateIfSafe` has no `.failed` branch. In a friends-beta this scenario (kill + no connectivity for 5+ minutes + successful server job) is rare but real.


## [LOW] Zero-notification window: APNs token registered mid-run suppresses the local ping while the server row has no token

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:159`  
**Dimension:** diff-correctness


**What happens:** The server decides whether to push using the device_token attached at job-SUBMIT time (startJob only adds `deviceToken` if NotificationService.shared.deviceTokenHex is non-nil at that moment; notifyJobFinished returns early when the row has no token). The client decides whether to post the local fallback using deviceTokenHex at COMPLETION time. run() itself kicks off requestAuthorization concurrently at line 80, so on the first-ever style learn (onboarding is exactly this) the permission dialog is on screen while compress/upload runs; if the user grants after the job was submitted, the token registers mid-poll. Result: server row has device_token=NULL → no push; client sees deviceTokenHex != nil → skips the local notification. The 'you can close the app — we'll notify you' promise breaks: closing the app after upload yields no notification of success or failure (kill-recovery still resumes the job on next launch, so only the ping is lost). The edit pipeline's default two-call path doesn't have this gap (it gates on the static serverNotifies/resumed flags, not on the live token).


**Evidence:** GeminiService.swift:235: `if let token = NotificationService.shared.deviceTokenHex { fields["deviceToken"] = token }` (submit-time snapshot). index.ts notifyJobFinished: `const push = await dbGetJobPush(jobId); if (!push?.device_token) return;`. StyleAnalysisCoordinator.swift:159-165 (and 225-231 in resumePipeline): `if NotificationService.shared.deviceTokenHex == nil { NotificationService.shared.notify(title: "Your style is ready ✨", ...) }` (completion-time check). run():80 `Task { await NotificationService.shared.requestAuthorization() }` races the pipeline. Trace: onboarding learn → permission dialog up during compress → job submitted tokenless → user grants → didRegister sets deviceTokenHex → user backgrounds → job done → server: no token, skip; client (on next foreground): token non-nil, skip → nobody notifies.


**Suggested fix:** Capture whether a token was attached at submit time (e.g. return/record it alongside the jobId, or snapshot deviceTokenHex before startStyleExtractionJob) and gate the local fallback on that snapshot instead of the live value.


**Verifier verdict:** UPHELD: Confirmed. GeminiService.startJob line 235 snapshots `deviceTokenHex` at submit time; the server's `notifyJobFinished` returns early when the row's `device_token` is NULL (confirmed in index.ts lines 221-222). StyleAnalysisCoordinator.run() line 80 fires `requestAuthorization()` concurrently, so on the first-ever onboarding learn the permission dialog races the upload. If the user grants after the job was submitted, the token registers mid-poll — server has no token (skips push); client sees non-nil token (skips local notification). The result is zero notification on close. The window is real but narrow: it requires an approve-after-submit timing AND the user backgrounding the app after that. Low severity for beta since the user can simply relaunch and the kill-recovery re-attaches.


## [LOW] IPHONEOS_DEPLOYMENT_TARGET bumped 17.0 → 26.0 — unrelated to the style flow and not required by the new app icon

**Where:** `FoodEditor.xcodeproj/project.pbxproj:237`  
**Dimension:** diff-correctness


**What happens:** The uncommitted pbxproj diff raises the target-level deployment target from 17.0 to 26.0 in BOTH Debug and Release (target settings override the project-level 17.0 at lines 173/216, so 26.0 is effective). The only other change in the commit area is ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon paired with the new Assets.xcassets/AppIcon.appiconset — which is a plain single-1024 'universal/ios' icon that works on every modern deployment target and does not need iOS 26. The bump silently drops installability on all iOS 17–25 devices and contradicts the codebase's documented compatibility stance (CLAUDE.md: 'iOS 17-compatible export (exportAsynchronously in a continuation — NOT the iOS-18 export())' — dead weight if 26.0 is real, a regression if it isn't). Likely an accidental Xcode 'Minimum Deployments' change made while adding the icon; if intentional, the iOS-17 workaround code and docs should be updated to match.


**Evidence:** project.pbxproj:237 and :263: `IPHONEOS_DEPLOYMENT_TARGET = 26.0;` (was 17.0 in both per `git diff HEAD`), alongside `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;` at :229/:255. FoodEditor/Assets.xcassets/AppIcon.appiconset/Contents.json: `{ "images": [{ "filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }] ... }` — no iOS-26-only icon format in use.


**Suggested fix:** Revert the two deployment-target lines to 17.0 unless dropping iOS 17–25 is a deliberate decision; if deliberate, note it in CLAUDE.md and retire the iOS-17 export shim.


**Verifier verdict:** UPHELD: Confirmed by git diff and reading project.pbxproj lines 237 and 263. The target-level Debug and Release configurations both changed from 17.0 to 26.0, overriding the project-level 17.0 setting at lines 173 and 216. The only co-changed setting is `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` with a standard universal 1024px icon (confirmed in Assets.xcassets/AppIcon.appiconset/Contents.json) that has no iOS 26 requirement. This change silently drops installability on iOS 17–25 and contradicts CLAUDE.md's documented iOS 17 compatibility stance. Likely an accidental Xcode 'Minimum Deployments' click while adding the icon. Low severity for the friends-beta since all test devices are presumably iOS 18+ and Apple's dev/TestFlight pipeline enforces this — but it must be reverted before any broader distribution.


## [LOW] Stale contract comments on both client and server claim style sends notifyOnFinish=false (it now sends true)

**Where:** `supabase/functions/gemini-proxy/index.ts:441`  
**Dimension:** diff-correctness


**What happens:** Behavior is correct — the client sends notifyOnFinish:true + notifyKind:"style" and the server forwards the boolean — but two doc comments in the SAME uncommitted diff still describe the old design and now directly contradict the code around them. The analyze handler's comment (index.ts:439-441) says 'style extraction sends false (not a user-facing edit)', two lines above the new notifyKind branch whose whole purpose is that style success DOES push. GeminiService.startJob's docstring (GeminiService.swift:220-221) says the same ('false for … style extraction (not a user-facing edit)') while its own caller three lines up (startStyleExtractionJob:212-215, whose doc was correctly updated) passes true. Since these comments define the client↔server push contract, a future edit 'restoring' the documented behavior would silently kill the closed-app style push and reintroduce the exact double/zero-notification balance this diff is tuning.


**Evidence:** index.ts:439-441: `// Whether THIS job's completion is the finish (→ push "cut is ready"). Default true keeps the\n// monolith correct; the two-call PERCEIVE call sends false (DECIDE still follows), and style\n// extraction sends false (not a user-facing edit).` vs GeminiService.swift:214-215: `startJob(..., notifyOnFinish: true, notifyKind: "style")`. GeminiService.swift:220-221 (unmodified in the diff): `/// True for the monolith edit-plan job; false for the two-call PERCEIVE call (DECIDE still follows) and\n/// for style extraction (not a user-facing edit).`


**Suggested fix:** Update both comments to state that style jobs send notifyOnFinish:true with notifyKind:"style" (push 'Your style is ready ✨', screen 'template') before this diff is committed/deployed.


**Verifier verdict:** UPHELD: Confirmed. index.ts line 441 says 'style extraction sends false (not a user-facing edit)' while the code two lines above (line 444) has the notifyKind branch whose whole purpose is the style push, and GeminiService.startStyleExtractionJob (line 214-215) passes `notifyOnFinish: true, notifyKind: 'style'`. The private `startJob` docstring at GeminiService.swift lines 220-221 also still says 'false for style extraction'. Behavior is correct; the comments are stale but directly contradict the code around them. A future 'restore documented behavior' edit would kill the closed-app style push silently. Low severity: no user-facing impact today, but a maintainability hazard in a codebase the team actively reads for the push contract.


## [LOW — MOOT] New proxy unconditionally inserts notify_kind, so deploying it before migration 0004 breaks ALL analyze jobs (edit + style), not just style

> **Adjudicated MOOT in round one:** a verifier queried the live Supabase project — migration 0004 is already applied (`notify_kind` column exists) and the deployed gemini-proxy v15 is byte-identical to the working tree, live since 2026-07-01. This is a deployment-ordering hypothetical only; no action needed. Kept for the record.

**Where:** `supabase/functions/gemini-proxy/index.ts:465`  
**Dimension:** backend-security


**What happens:** The uncommitted diff makes every `analyze` job insert include the new `notify_kind` column, but that column only exists after migration 0004 is applied. Nothing enforces migrate-before-deploy ordering. If the new Edge Function ships before 0004 lands, PostgREST rejects the INSERT with an unknown-column error, `dbInsertJob` throws, and the switch's outer catch returns a generic 502 — for EVERY analyze op (the monolith edit job, the two-call PERCEIVE job, AND the style job). The entire server-side analysis pipeline goes down, and the generic 502 gives no hint that a migration is missing.


**Evidence:** dbCreateJob row now always carries the new column (index.ts:456-466):
  const jobId = await dbInsertJob({
    status: "active", ... 
    notify_kind: notifyKind,   // <-- new; column added only by 0004
  });
dbInsertJob hard-throws on any non-2xx (index.ts:88):
  if (!r.ok) throw new Error(`insert jobs failed: ${r.status} ${await r.text()}`);
Outer catch masks the cause (index.ts:489-491):
  } catch (e) { return json({ error: "Proxy request failed" }, 502); }
Migration that must land first (0004_jobs_notify_kind.sql):
  alter table public.jobs add column if not exists notify_kind text;
Trace: deploy index.ts → apply 0004 (wrong order) → client GeminiService.startJob POSTs analyze → PostgREST 400 "Could not find the 'notify_kind' column" → dbInsertJob throws → 502 → GeminiService.swift:243-244 throws GeminiError.http(502) → every analysis (edit + style) fails until 0004 is applied.


**Suggested fix:** Apply migration 0004 strictly before deploying the new function (document the ordering in the deploy runbook/README), and/or make the insert defensive: only add `notify_kind` to the row object when it differs from the default, or wrap the insert so a PGRST204 unknown-column error degrades to inserting without notify_kind (NULL == edit) rather than 502-ing the whole pipeline.


**Verifier verdict:** UPHELD: The code confirms it: line 465 of index.ts now always passes `notify_kind: notifyKind` in the `dbInsertJob` row object, and `dbInsertJob` hard-throws on any non-2xx response (line 88). If migration 0004 has not been applied, PostgREST will return a 400 'could not find column notify_kind', the throw propagates to the outer catch at line 489-491, and every `analyze` op returns a generic 502 — affecting edit jobs, PERCEIVE jobs, and style-learning jobs equally. The failure description is accurate. However, the severity for a friends-beta is low rather than medium: (1) this is a one-time deployment sequencing mistake, not a runtime logic bug — the developer applies the migration and the function in the same deploy session; (2) the new migration file (0004_jobs_notify_kind.sql) uses `ADD COLUMN IF NOT EXISTS`, meaning it is safe to apply first with no downside; (3) if the developer follows the standard Supabase workflow (push migration, then deploy function), or simply applies migration first, the issue never manifests; (4) a small-team friends-beta has one deployer who will notice the 502 immediately on their own first use and fix it in minutes. The finding is real as a deployment-ordering risk but is not a latent code defect that can bite silently in production; it would be caught and corrected on the first test run.


## [LOW] runJob.fail() always sends a failure APNs push ignoring notifyOnFinish, so an edit-pipeline server failure double-notifies (server push + ungated client-local notification)

**Where:** `supabase/functions/gemini-proxy/index.ts:265`  
**Dimension:** backend-security


**What happens:** The worker's success push is correctly gated by `notifyOnSuccess` (the client's notifyOnFinish flag), but `fail()` pushes unconditionally. On the edit pipeline the client's AnalysisCoordinator ALSO posts a local "Analysis hit a snag" notification on failure with no gate (unlike the newer StyleAnalysisCoordinator, which gates its failure notify on `deviceTokenHex == nil`). Result: any edit-pipeline server-side failure on a device with a registered APNs token produces TWO identical "Analysis hit a snag" alerts — the server APNs push plus the client-local one. Reproducible in both release (monolith, notifyOnFinish=true) and DEBUG (two-call PERCEIVE, notifyOnFinish=false — where the client explicitly does NOT expect the server to notify).


**Evidence:** Server: success push honors the flag but failure push does not (index.ts:265-268, 342):
  const fail = async (error: string) => {
    await dbUpdateJob(jobId, { status: "failed", error });
    await notifyJobFinished(jobId, false);   // always pushes, even when notifyOnSuccess=false
  };
  ...
  if (notifyOnSuccess) await notifyJobFinished(jobId, true);   // success is gated
Client edit path posts an UNGATED local failure notify (AnalysisCoordinator.swift:211 and :434):
  NotificationService.shared.notify(title: "Analysis hit a snag", body: message, screen: "analysis")
Contrast: the style coordinator DOES gate the same notify (StyleAnalysisCoordinator.swift:175):
  if NotificationService.shared.deviceTokenHex == nil { NotificationService.shared.notify(title: "Style analysis hit a snag", ...) }
Trace: edit analyze job with a device token fails server-side → fail() APNs-pushes "Analysis hit a snag" → client awaitJobResult throws → AnalysisCoordinator catch posts a second local "Analysis hit a snag" (foreground delegate shows both banners; closed-app gets the push then a second local one on relaunch-resume).


**Suggested fix:** Gate the edit coordinator's failure notification the same way the style coordinator does (only post locally when deviceTokenHex == nil), matching the success-path serverNotifies logic; or make fail() respect the flag by only pushing failure when notifyOnSuccess (accepting that a closed-app PERCEIVE failure then relies on the client's relaunch-resume to surface it).


**Verifier verdict:** UPHELD: The code confirms the asymmetry: `fail()` (lines 265-268) calls `notifyJobFinished(jobId, false)` unconditionally, while the success path gates on `notifyOnSuccess` (line 342). On the client side, `AnalysisCoordinator.runPipeline`'s catch block (line 211) calls `NotificationService.shared.notify(title: 'Analysis hit a snag', ...)` with no gate — no check on `deviceTokenHex` or `serverNotifies`. This means for any edit-pipeline failure where a device token is registered, both the server APNs push and a client-local notification fire. The style coordinator correctly gates the client-side failure notification on `deviceTokenHex == nil` (line 175), so style jobs do not double-notify. The double is real and reproducible on any device with Push enabled when a server-side analyze job fails. Severity is low for a friends-beta: (1) the double notification only fires on an error path, not the happy path; (2) it produces two identical banners rather than corrupting data or blocking the user; (3) on a device that has the app foregrounded, the UNUserNotificationCenter foreground delegate typically suppresses local notifications anyway depending on configuration; (4) the fix is a one-line gate mirroring the style coordinator's pattern. Real bug, cosmetic/UX impact only.


## [LOW] status op returns HTTP 404 for both a genuinely-missing job and a transient DB read error; the Swift client mis-classifies 404 as a transient blip and polls uselessly for the full 300s

**Where:** `supabase/functions/gemini-proxy/index.ts:481`  
**Dimension:** backend-security


**What happens:** `dbGetJob` collapses two distinct conditions to null — a real 0-row result AND any non-ok PostgREST fetch (transient DB/network hiccup) — and the status handler maps null to a 404 "job not found". On the client, `jobStatus` turns any non-200 into `GeminiError.http`, and `awaitJobResult` treats every error except `.badRequest` as a retryable blip. So a 404 is retried every 2.5s until the 300s deadline, then surfaced as a misleading `timedOut` ("server job didn't finish in time"). For a transient DB error this masquerade happens to retry (benign), but a truly-absent job (e.g., a stale persisted jobId re-attached after a Supabase project-ref change, or once the planned created_at cleanup cron starts deleting old rows) burns 300s of pointless polling and reports the wrong failure reason.


**Evidence:** dbGetJob returns null on ANY non-ok fetch, not just 0 rows (index.ts:109-111):
  if (!r.ok) return null;
  const rows = await r.json();
  return rows[0] ?? null;
status maps null → 404 (index.ts:481-483):
  const row = await dbGetJob(jobId);
  if (!row) return json({ error: "job not found" }, 404);
Client turns 404 into GeminiError.http (GeminiService.swift:258-259) which awaitJobResult retries because only .badRequest is fatal (GeminiService.swift:286-292):
  } catch let e as GeminiError { if case .badRequest = e { throw e }  // else swallow + retry
Trace: resume/poll a jobId whose row is absent → status 404 → GeminiError.http(404) → not .badRequest → retried for 300s → GeminiError.timedOut("server job didn't finish in time") shown instead of a clear 'job not found'.


**Suggested fix:** Distinguish a genuine 0-row miss from a fetch failure in dbGetJob (only 404 when the query succeeded with no rows; surface transient fetch errors as 502 so the retry semantics are correct), and/or have the client treat a 404 from the status op as a terminal 'job gone' rather than a transient blip.


**Verifier verdict:** UPHELD: The code confirms the finding. `dbGetJob` returns null on any non-ok PostgREST response AND on a genuine 0-row result (lines 109-111); the status handler maps both to a 404 'job not found' (line 482); and `awaitJobResult` only treats `GeminiError.badRequest` (which comes from `.failed` job rows) as fatal — all other errors including `GeminiError.http(404)` are logged as transient blips and retried (lines 286-292). A true missing-job scenario burns the full 300-second polling window and surfaces a misleading `timedOut` error instead of 'job not found'. In a friends-beta this is genuinely triggerable by the planned row-cleanup cron (mentioned in KNOWN_ISSUES), a project-ref change mid-session, or a stale persisted job ID after a Supabase project reset. The misleading error message makes debugging harder. However, severity is low because: (1) today no cleanup cron is running, so missing-job cases are rare (only after a project-ref change or a manual DB wipe); (2) the 300-second wait, while annoying, eventually clears; (3) a transient DB read error masquerading as a 404 and being retried is actually the correct behavior for the transient case — the conflation only hurts the true-missing scenario; (4) fixing requires distinguishing 0-row from a non-ok PostgREST fetch in `dbGetJob`, which is a clean two-line change. Real bug, minor UX impact in current beta usage.


## [LOW] Completion-notification gating checks deviceTokenHex at the wrong time — a fresh user's first style learn can finish (or fail pre-job) with no notification from anywhere

**Where:** `FoodEditor/Services/StyleAnalysisCoordinator.swift:159`  
**Dimension:** beta-failure-modes


**What happens:** Two mis-fires of the `deviceTokenHex == nil` dedup gate, both hitting exactly the first-run beta case. (a) Success race: run() fires requestAuthorization concurrently at pipeline start — the FIRST-ever permission dialog appears over the analyzing screen while compress+upload proceed. If the user hasn't answered (or APNs registration hasn't completed) by the time startStyleExtractionJob POSTs, the job row gets no device_token → the server will never push. If the token then registers before completion, the client-side fallback sees deviceTokenHex != nil and stays silent too → the user who backgrounded the app gets zero 'style is ready' ping and only discovers the result on the next manual open. (b) Failure side: run()'s catch also gates the local 'Style analysis hit a snag' on deviceTokenHex == nil, assuming the server pushed — but compress/upload failures happen BEFORE any server job exists, so no failure push exists either; a token-holding user who tapped away mid-upload (upload dies ~30s after backgrounding when the BackgroundActivity assertion expires) gets no notification and returns to a stale screen. The edit pipeline posts its failure notification unconditionally; the style flow's stricter gate creates these silent holes.


**Evidence:** GeminiService.startJob attaches the token at submit time: `if let token = NotificationService.shared.deviceTokenHex { fields["deviceToken"] = token }` (GeminiService.swift:235). StyleAnalysisCoordinator.swift:159 (success) and :175 (failure):
```
if NotificationService.shared.deviceTokenHex == nil {
    NotificationService.shared.notify(title: "Your style is ready ✨", ...)
```
Trace (b): token registered → user starts create learn → backgrounds during upload → URLSession dies after the ~30s background grace → catch: no server job ⇒ no push; deviceTokenHex != nil ⇒ no local ping → silence.


**Suggested fix:** Gate the local fallback on 'was a token attached to THIS job at submit time' (record it alongside the jobId) rather than the current deviceTokenHex; for pre-job failures (no jobId yet) always post the local failure notification.


**Verifier verdict:** UPHELD: Both sub-cases are confirmed by the code. (a) Token race on first run: `requestAuthorization()` is fired as a detached `Task` at run() line 80, concurrently with compress+upload. `NotificationService.deviceTokenHex` is initialized from UserDefaults (line 16 of NotificationService.swift) — on first-ever install this is nil. If APNs registration completes after `startStyleExtractionJob` POSTs (likely on first run — authorization dialog + APNs roundtrip takes several seconds, while the job POST is quick), the server job row has no `device_token` → no APNs push on completion. The client-side local fallback then checks `deviceTokenHex == nil` → by completion time the token HAS arrived → local notify also skipped. Silent success. (b) Failure path: pre-job failures (compress error, upload error) happen before any server job is created, so no server push exists. With `deviceTokenHex != nil`, the `if deviceTokenHex == nil` gate at line 175 prevents the local notify. A token-registered user who backgrounds mid-upload (URLSession dies ~30s after backgrounding per BackgroundActivity) gets zero notification. Both scenarios are real. Severity is low (not medium) for a friends-beta because: (a) affects only first-ever install before token persists; (b) pre-job upload failures that also involve backgrounding are edge-case combinations; (c) users on a friends-beta will typically open the app and notice the result without needing a push.


## [LOW] Style-profile JSON is accepted with zero validation — any JSON object (even {}) becomes a 'successful' all-defaults template

**Where:** `FoodEditor/Models/StyleTemplate.swift:280`  
**Dimension:** parsing-robustness


**What happens:** The style-extraction job is the only Gemini call that runs with NO responseSchema (GeminiService.startStyleExtractionJob passes schema: nil), i.e. free-form generation — the exact case where wrapped output ({"style_profile": {...}}), renamed keys, or a refusal-shaped JSON object is most likely. Yet StyleProfileRaw's decoder is total-leniency: every field is `(try? …) ?? default`, so ANY JSON object — including `{}` — decodes successfully into an all-defaults profile (styleBrief "", confidence 0, empty everything). StyleAnalysisCoordinator then has no sanity gate: it builds StyleTemplate(from:) → name falls back to "My style", derives 6 default habits, sets phase = .done, calls StyleJobStore.clear() (the paid job result is now unrecoverable), and the server has already pushed "Your style is ready ✨". The creator lands on a review page for a blank/garbage template presented as success. Contrast with the edit path, which at minimum runs EditPlanValidator and logs a report; the style path never checks a single field. This is exactly 'style-analysis JSON handled less defensively than EditPlan.parse' — it fails silently instead of loudly.


**Evidence:** GeminiService.swift:215 `startJob(..., schema: nil, ...)` (no responseSchema). StyleTemplate.swift init(from:) lines 261-277: every field is `(try? c.decode(...)) ?? default`, e.g. `styleBrief = (try? c.decode(String.self, forKey: .styleBrief)) ?? ""` and `confidence = try c.lenientDouble(.confidence) ?? 0` — so `parse(fromRawModelText:)` (line 280) succeeds for ANY top-level JSON object. Trace: Gemini returns `{"style_profile": { ...real fields... }}` (wrapper key, plausible without schema) → JSONDecoder().decode(StyleProfileRaw.self, ...) succeeds with ALL defaults → StyleAnalysisCoordinator.swift:148-155 `let merged = StyleProfileRaw.merge(profiles); let built = StyleTemplate(from: merged, count: clips.count); template = built; phase = .done; StyleJobStore.clear()` → RootView.onChange(create.coordinator.phase == .done) routes to .createReview with a template named "My style", 0% confidence, empty summary. No error, no retry path, job record deleted.


**Suggested fix:** After StyleProfileRaw.parse, gate on minimum viability (e.g. `guard !profile.styleBrief.isEmpty || profile.confidence > 0 else { throw EditPlanParseError.decodeFailed("style profile missing required fields") }`) so the coordinator's existing .failed/Retry path fires. Longer term: attach a responseSchema to the style job like every other call.


**Verifier verdict:** UPHELD: The mechanics are exactly as described. StyleProfileRaw.parse() extracts first-to-last brace and decodes with 100% leniency, so any JSON object — including {} or a wrapper like {"style_profile":{...}} — decodes successfully into an all-defaults StyleProfileRaw. StyleAnalysisCoordinator then calls StyleJobStore.clear() unconditionally at line 155, making recovery impossible, and phase flips to .done. The user lands on a review page named 'My style' with 0% confidence. However, two things reduce the practical severity for a friends-beta. First, the exaggerated claim that a wrapper key is 'most likely' without a responseSchema: the style prompt runs at temperature=0, and Gemini reliably outputs flat JSON for a well-specified prompt with explicit schema-in-prose and a concrete example — a wrapper key is plausible but uncommon in practice. Second, the outcome is not a crash or silent data loss: the user sees a visible TemplateEditorView with a blank summary and can edit it or cancel; it is bad UX but recoverable by the user. The bug is real and worth a follow-up sanity gate (e.g. check styleBrief.isEmpty || confidence == 0 && signatureMoves.isEmpty), but the risk of hitting it in a small friends-beta is low.


## [LOW] An empty/degenerate EditPlan ships as success: lenient decode falls back to [] wholesale, the validator scores an empty plan 1.00, and ship() has no minimum-viability gate

**Where:** `FoodEditor/Services/AnalysisCoordinator.swift:241`  
**Dimension:** parsing-robustness


**What happens:** Three layers each assume another layer catches the degenerate case, and none does. (1) EditPlan's decoder uses all-or-nothing array fallbacks: `segments = (try? c.decode([Segment].self, ...)) ?? []` — one malformed element (a null in the array, `"segments": null`, or a wrapper key around the whole plan) silently empties the ENTIRE segments list rather than dropping one entry; same for finalEditOrder ([Int] has no lenient string-int path even though scalar ids do via lenientInt). (2) EditPlanValidator.validate has no rule for zero segments or an empty effective spine — an empty plan reports "Plan valid — 0 segments, score 1.00" (the DEBUG selfCheck even asserts this). (3) ship() installs the store, saves a project, flips .done unconditionally. Result: the server has already pushed "Your cut is ready 🍴" (monolith, notifyOnFinish=true), the user taps into a cut with zero clips, AnalysisJobStore.clear() has discarded the recovery record, and there is no Retry (phase is .done, not .failed). Two-call variant: if DECIDE's `final_edit_order` fails [Int] decode (e.g. string ids) it becomes [] → EditPlanAdapter marks every non-b-roll shot keep:false → EditPlanStore.order is empty → a "0s" cut ships with the client's own "Your cut is ready 🍴 — N moments found" ping. Release builds default to the monolith path (FeatureFlags.twoCallPipeline is false outside DEBUG), where the schema-less-tolerant decode matters most.


**Evidence:** EditPlan.swift:281-284: `finalEditOrder = (try? c.decode([Int].self, forKey: .finalEditOrder)) ?? []; segments = (try? c.decode([Segment].self, forKey: .segments)) ?? []`. Segment.init(from:) line 129 `let c = try decoder.container(...)` throws for a non-object element → the whole [Segment] decode fails → []. EditPlanValidator.swift:94 `if let first = ordered.first {` — all coverage/order/b-roll checks no-op on an empty plan; selfCheck line 246-249: "EMPTY — no segments. Should not crash; score stays 1.0". AnalysisCoordinator.ship() lines 241-305: no guard on plan.segments.isEmpty or on an empty spine before `session.store = EditPlanStore(plan: plan, ...); phase = .done; projects.startNew(from: plan)`. EditDecisions.swift:90 `finalEditOrder = (try? c.decode([Int].self, ...)) ?? []` → EditPlanAdapter.adapt: `var kept = Set(order)` → all shots keep:false → EditPlanStore.swift:115 `orderedKept = plan.finalEditOrder.filter { keepIds.contains($0) }` = [] → order = [].


**Suggested fix:** Add a viability gate in ship() (or at the end of parse/adapt): `guard !plan.segments.isEmpty, plan.segments.contains(where: { $0.keep }) else { throw EditPlanParseError.decodeFailed("plan has no usable segments") }` so the existing .failed + Retry + "hit a snag" path fires instead of shipping a blank success. Optionally decode arrays per-element (lossy) so one bad element drops one entry, not all.


**Verifier verdict:** UPHELD: All three claimed gaps exist in the code. EditPlan.swift:283 uses (try? ...) ?? [] for segments, so one malformed element or a null value throws the whole array away silently. The validator's selfCheck at line 246-249 explicitly confirms an empty plan reaches ship() with score 1.0. ship() at line 284 installs the store unconditionally. However, the monolith path (the release default, FeatureFlags.twoCallPipeline == false) submits with responseSchema — a strict structured-output schema that marks segments as a required ARRAY. Gemini's structured output greatly reduces the probability of returning {} or segments: null because the schema forces the field. A single malformed element inside a valid array could still cause [] (because the [Segment] decode fails on the first bad element and the whole array falls to []), but that requires Gemini to violate its own required schema — unusual at temperature=0 in a friends-beta but not impossible. On the two-call PERCEIVE→DECIDE path (debug-only), the risk is higher. Overall this is a real structural gap but the trigger probability in beta against the structured schema is low enough to call it low rather than medium.


## [LOW] ContentIndexNormalizer trusts the model-reported duration_seconds as the clamp bound (ground truth is in hand but never passed) and never drops zero-length shots

**Where:** `FoodEditor/Models/ContentIndexNormalizer.swift:13`  
**Dimension:** parsing-robustness


**What happens:** normalize() clamps every shot to [0, dur] where dur is PERCEIVE's own `duration_seconds` (a model-generated NUMBER; the prompt asks for "the exact length" but nothing verifies it). If the model under-reports — a plausible Flash failure mode given its documented segmentation instability — every shot past the false duration collapses to a zero-length shot AT t=dur: `end = max(start, min(s.endSeconds, dur))`. Unlike zero-length talk_spans (explicitly dropped at line 45), zero-length SHOTS survive, get renumbered, and are serialized into the DECIDE prompt; if DECIDE orders one, the adapter emits a zero-length Segment (the validator logs nonPositiveDuration but never gates) and Clip.sourceDuration clamps it to a 0.1s sliver. The real damage is silent amputation of all footage past the wrong duration. The caller (AnalysisCoordinator.decideAndShip) holds the measured proxy duration (`processed.metadata.duration` — the same value it passes to EditPlanValidator) but normalize() takes no duration parameter.


**Evidence:** ContentIndexNormalizer.swift:13 `let dur = index.durationSeconds > 0 ? index.durationSeconds : (index.shots.map(\.endSeconds).max() ?? 0)`; lines 19-20 `let start = max(0, min(s.startSeconds, dur)); let end = max(start, min(s.endSeconds, dur))` — a shot with startSeconds >= dur becomes (dur, dur) and is appended at line 32 (only talk spans have the `if b - a < 0.05 { dropped += 1; continue }` guard, line 45). AnalysisCoordinator.swift:342 `let (index, normActions) = ContentIndexNormalizer.normalize(parsedIndex)` — `processed.metadata.duration` is available in the same scope (used at line 262 for the validator) but not passed. Trace: PERCEIVE returns duration_seconds 30 for a 60s proxy → shots at 30-60s all become zero-length at t=30 → DECIDE never sees the second half → the shipped cut silently lacks half the footage, with only console log evidence.


**Suggested fix:** Change to `normalize(_ index:, proxyDuration: Double)` and use the measured duration when it disagrees with the model's by more than tolerance (log the correction); drop zero-length shots the same way zero-length talk spans are dropped.


**Verifier verdict:** UPHELD: The normalizer at line 13 derives dur from index.durationSeconds, not from processed.metadata.duration, and AnalysisCoordinator.decideAndShip at line 342 calls normalize() without passing the measured proxy duration (which is available in scope at line 262 where it is passed to the validator). Zero-length shots that result from clamping at a wrong dur are not filtered (only talkSpans under 0.05s are dropped at line 45). However, there are two important scope-limitters. First, the two-call path is guarded by FeatureFlags.twoCallPipeline which is false outside DEBUG — so this code path is not exercised in any beta build. Second, even in debug, the PERCEIVE prompt asks for duration as 'the exact length of the entire video,' and Flash's instability is in shot segmentation count, not in total-duration reporting — under-reporting total duration by half would be an extreme model error. The fix (pass processed.metadata.duration as a clamping floor into normalize()) is straightforward and correct, but the impact in production is nil until twoCallPipeline is enabled. Real finding, low adjusted severity for the current beta.


## [LOW] Monolith path: missing/duplicate segment ids all collapse to the same key and silently shadow segments (lenientInt ?? 0 + first-wins Dictionary; validator has no duplicate-segment-id rule)

**Where:** `FoodEditor/Models/EditPlan.swift:130`  
**Dimension:** parsing-robustness


**What happens:** Segment.init defaults a missing/unparseable id to 0 (`lenientInt(.id) ?? 0`). If two or more segments arrive without ids (or with duplicate ids — nothing in the responseSchema can enforce uniqueness), every id-keyed structure keeps only the FIRST: EditPlanStore.segmentsById, EditPlanRepair's byId, and EditPlanValidator's byId all build with `uniquingKeysWith: { a, _ in a }`. All lookups (makeClip, renderSlots, sourceLength, b-roll repair) then resolve the duplicate id to the first segment's timestamps, so the other segments' footage becomes unreachable while still counting in keepIds/cutTray (duplicate entries). EditPlanValidator checks duplicates in final_edit_order (orderDuplicate) but has NO check for duplicate ids in segments[], so this arrives at the store completely unflagged. The two-call path is immune (ContentIndexNormalizer renumbers 0..n-1), but release builds default to the monolith (FeatureFlags.twoCallPipeline is false in non-DEBUG), where this is live.


**Evidence:** EditPlan.swift:130 `id = try c.lenientInt(.id) ?? 0`. EditPlanStore.swift:100 `let byId: [Int: Segment] = Dictionary(plan.segments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })`. EditPlanValidator.swift:119-134 — the only duplicate rule is `.orderDuplicate` over plan.finalEditOrder; nothing iterates segments for id collisions. Trace: model emits segments 0..12 but omits `id` on two of them → both decode as id 0 → segmentsById[0] is the first; the two shadowed segments can never be previewed/exported (clip(0) always maps to the first segment's in/out), and cutTray/keepIds contain repeated 0s that make Triage/restore behave on the wrong footage — with a clean validation report.


**Suggested fix:** Add a `duplicateSegmentId` violation to EditPlanValidator, and in the decoder prefer failing (or re-numbering, as the two-call normalizer does) when ids collide rather than silently shadowing.


**Verifier verdict:** UPHELD: Every claim checks out against the code. Segment.init at EditPlan.swift:130 defaults a missing or unparseable id to 0. EditPlanStore.init at line 100 builds segmentsById with uniquingKeysWith: { a, _ in a }, keeping only the first segment per id. EditPlanRepair.repairBroll and EditPlanValidator both build the same first-wins dictionary. The validator's duplicate check (line 120-134) covers final_edit_order entries, not segment ids. So duplicate segment ids produce silently shadowed segments with no log entry. However, the monolith path runs with responseSchema that marks 'id' as a required INTEGER and uses structured output at temperature=0 — Gemini reliably emits sequential integers when given a strict schema. The schema cannot enforce uniqueness, but in practice with structured output and temperature=0 Gemini has never been observed to emit duplicate ids in this project's model calls. The damage if it occurs is real (affected segments become unreachable) but the trigger in a friends-beta with the structured schema in place is very low probability. Worth adding a duplicate-id check to EditPlanValidator for better observability, but not a blocking beta risk.


---

# Refuted claims (checked, NOT real bugs)
