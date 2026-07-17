import Foundation
import Observation
import UIKit

/// Owns the **style-learning** pipeline (extraction call 1): for each selected finished video, compress →
/// upload → extract a `StyleProfileRaw`, then merge the per-video profiles into one `StyleTemplate`.
///
/// Mirrors `AnalysisCoordinator`'s exactly-once design (phase flips synchronously before the first await;
/// idempotent on the clip-set signature; the Task is held here so analysis survives the view disappearing),
/// but produces a template rather than an EditPlan and does NOT create a project. Reused by onboarding
/// (step 3) and the create-new-template flow (step 9, M6).
@MainActor
@Observable
final class StyleAnalysisCoordinator {
    enum Phase: Equatable { case idle, running, done, failed(String) }

    /// Where in the learn we are — drives the Screening Room's lens cadence and the leave pill.
    /// Mirrors `AnalysisCoordinator.Stage` for the edit pipeline.
    enum LearnStage: Equatable { case compressing, uploading, watching, synthesizing }

    private(set) var phase: Phase = .idle
    private(set) var stage: LearnStage = .compressing
    private(set) var progress: Double = 0
    private(set) var label = "Getting started"
    private(set) var analyzedCount = 0        // videos finished (drives the mockup's "{n} of {N}" counter)
    private(set) var totalCount = 0
    private(set) var template: StyleTemplate?
    /// First clip's frame — saved as the template's library-tile thumbnail.
    private(set) var posterImage: UIImage?

    /// Clips whose on-device compress has finished (MainActor-only; TaskGroup children hop here).
    private var compressedCount = 0

    /// True while ANY clip's on-device compress is running — the one step iOS suspends when the app
    /// backgrounds. Mirrors `AnalysisCoordinator.isCompressing`.
    var isCompressing: Bool { phase == .running && stage == .compressing }

    /// "Free to go" — true only once EVERY video's job is handed to the server (`stage == .watching`
    /// onward), so the promise never lies. It used to flip at `.uploading` (all clips COMPRESSED), but
    /// an upload only rides a ~30s `BackgroundActivity` grace: leaving mid-upload could strand a clip
    /// that never reaches the server, stalling the batch with no push. Compress AND upload both pin the
    /// app open now; the affordance appears the moment the work is genuinely server-side. False at
    /// `.idle` so the leave pill's first frame is never a sage flash that flips backward to ochre.
    var canLeave: Bool {
        switch phase {
        case .running: return stage == .watching || stage == .synthesizing
        case .done:    return true
        default:       return false
        }
    }

    /// MainActor event from each TaskGroup child the moment its compress returns.
    private func noteClipCompressed() {
        compressedCount += 1
        if phase == .running, stage == .compressing, compressedCount >= totalCount {
            stage = .uploading
        }
    }

    private var signature: String?
    private var task: Task<Void, Never>?

    /// Which flow owns this coordinator's jobs — gates kill-recovery so onboarding and the create flow
    /// never resume each other's persisted job (see `StyleJobStore`).
    let origin: StyleJobOrigin

    /// REFINEMENT (M6): when set, Phase C re-consolidates the base template's persisted sources + the new
    /// per-video profiles, and `TemplateRefiner.apply` merges the result back WITHOUT clobbering user
    /// edits. `diff` carries the mini-reveal's "what changed" story.
    private var refineBase: StyleTemplate?
    private(set) var diff: TemplateDiff?

    /// Per-clip prep progress (compress+upload+job-start), aggregated into the 0→0.5 phase-A window —
    /// the clips prep CONCURRENTLY, so overall progress is the average, not a sequential sweep.
    private var clipProgress: [Double] = []
    private func setClipProgress(_ i: Int, _ p: Double) {
        guard clipProgress.indices.contains(i) else { return }
        clipProgress[i] = max(clipProgress[i], min(1, p))
        progress = 0.5 * (clipProgress.reduce(0, +) / Double(clipProgress.count))
    }

    /// Fires "Open Vela to finish" if the app backgrounds while a compress is running (iOS suspends the
    /// AVFoundation export; the upload/server phases survive on their own). Lives on the COORDINATOR so
    /// all three instances (onboarding / create / refine) are covered with zero view wiring — RootView's
    /// scenePhase nudge can't reach onboarding's @State coordinator.
    /// `nonisolated(unsafe)`: written once in `init`, read once in nonisolated `deinit` — no concurrent
    /// access by construction (NotificationCenter's removeObserver is itself thread-safe).
    nonisolated(unsafe) private var backgroundObserver: (any NSObjectProtocol)?

    init(origin: StyleJobOrigin) {
        self.origin = origin
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.nudgeIfCompressing() }
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    private func nudgeIfCompressing() {
        guard isCompressing else { return }
        NotificationService.shared.notify(
            title: "Open Vela to finish",
            body: "Compression couldn't complete while you were away — please go back to the app to finish prepping your footage.",
            id: "compress-nudge")   // stable id → coalesces with the edit pipeline's nudge, never stacks
    }

    /// Entry point for the "sharpen this style" flow — same idempotent machinery, refined Phase C.
    func start(clips: [SourceClip], refining base: StyleTemplate) {
        refineBase = base
        start(clips: clips)
    }

    // MARK: entry points

    func start(clips: [SourceClip]) {
        // Empty clips = a display-only entry (a post-kill route into `.createAnalyzing`, where the picked
        // clips are gone). NEVER launch with nothing — that would clear the kept recovery record and clobber
        // any real error with "No videos to learn from." Just re-attach a persisted job when idle; otherwise
        // the current phase (.running/.done/.failed) is already the right thing to show.
        if clips.isEmpty {
            if phase == .idle { resumeIfPending() }
            return
        }
        let sig = AnalysisCoordinator.signature(for: clips)
        // If a server job for this exact submission is still pending (persisted across a kill), re-attach
        // to it rather than starting a second (paid) extraction.
        if phase == .idle, let pending = StyleJobStore.load(),
           pending.origin == origin, pending.clipSignature == sig {
            resumeIfPending()
            return
        }
        switch phase {
        case .running:                                   return
        case .done where signature == sig && template != nil: return
        case .failed where signature == sig:             return
        default:                                         break
        }
        launch(clips: clips, signature: sig)
    }

    func retry(clips: [SourceClip]) {
        task?.cancel()
        let sig = AnalysisCoordinator.signature(for: clips)
        // If a recovery record survives, the server job may still be alive/finishing (only a `.timedOut`
        // soft-fail keeps a record — terminal failures clear it). Re-poll it instead of paying for a second
        // extraction. Matches on same clips OR clips-gone-after-kill.
        if let pending = StyleJobStore.load(), pending.origin == origin,
           clips.isEmpty || pending.clipSignature == sig {
            phase = .idle            // resumeIfPending requires .idle
            resumeIfPending()
            return
        }
        launch(clips: clips, signature: sig)   // launch() clears any stale record before a fresh paid run
    }

    /// Stop waiting on a live run WITHOUT destroying it: the server job keeps running and the recovery record
    /// is kept, so a later `start()` with the same clips (or the next app launch) re-attaches and delivers the
    /// paid result. Drives the Analyzing screen's cancel affordance. No-op unless actively running.
    func cancel() {
        guard phase == .running else { return }
        task?.cancel()
        task = nil
        phase = .idle
        stage = .compressing
        compressedCount = 0
        progress = 0
        Log.gemini("Style learn cancelled by user — job kept server-side for re-attach.")
    }

    /// Wipe in-memory state back to idle. Does NOT touch StyleJobStore (the caller decides whether the record
    /// should survive). Used when a review is saved or discarded so a stale `.done`/`.failed` phase can't keep
    /// driving the Home card.
    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        stage = .compressing
        compressedCount = 0
        progress = 0
        label = "Getting started"
        template = nil
        posterImage = nil
        signature = nil
        analyzedCount = 0
        totalCount = 0
        refineBase = nil
        diff = nil
    }

    /// Whether a kill-recovery record for THIS flow is on disk — drives the "does Retry actually do anything"
    /// decision in the error screen. Not observation-tracked, but the record's presence always changes in
    /// lockstep with a phase change, so any view reading it is already re-rendered by that transition.
    var hasPendingRecord: Bool { StyleJobStore.load()?.origin == origin }

    private func launch(clips: [SourceClip], signature sig: String) {
        StyleJobStore.clear()   // a fresh paid run supersedes any stale recovery record
        signature = sig
        phase = .running
        stage = .compressing
        compressedCount = 0
        progress = 0
        analyzedCount = 0
        totalCount = clips.count
        label = "Getting started"
        template = nil
        // The long analysis now runs server-side (one job per video), so only the on-device uploads need
        // a background-task assertion — applied per-upload inside `run`. Once the uploads finish the
        // creator can close the app and the work still completes.
        task = Task { [weak self] in
            await self?.run(clips: clips)
        }
    }

    // MARK: pipeline — one extraction per video, then merge

    private func run(clips: [SourceClip]) async {
        Task { await NotificationService.shared.requestAuthorization() }
        guard !clips.isEmpty else { phase = .failed("No videos to learn from."); return }
        posterImage = clips.first?.thumbnail   // tile thumbnail for the saved template

        // True once the server extraction jobs exist — gates the "keep the record on timeout" policy so a
        // PRE-job failure (compress/upload) is treated as terminal, not as a recoverable in-flight job.
        var jobStarted = false
        do {
            let n = clips.count

            // Phase A (0 → 50%) — compress + upload EVERY video CONCURRENTLY and start one server job
            // per video. The extractions already run in parallel server-side; this removes the on-device
            // serialization too (clip 2's compression used to wait for clip 1's entire compress+upload),
            // so a 3-video learn preps in roughly the time of its slowest clip instead of the sum. A
            // failed prep is terminal for the submission (matching the old pre-job policy); any sibling
            // jobs that already started are orphans the server-side reaper cleans up.
            clipProgress = [Double](repeating: 0, count: n)
            label = n > 1 ? "Uploading your \(n) videos" : "Uploading your video"
            // One batch id for the whole submission: the server latches on it so the "style is ready"
            // push fires ONCE — when the LAST sibling job finishes — instead of once per video.
            let batchId = UUID().uuidString.lowercased()
            // Server-chained consolidation: author the COMPLETE merge request NOW (the only moment the
            // client is guaranteed alive with the prompt inputs — refine bases, confirmed quotes,
            // suppressions) with «VELA_SRC_i» placeholders for the not-yet-extracted results. The proxy
            // substitutes + runs it the instant the last extraction lands, so the ready push means the
            // template is genuinely BUILT (measured 74s of client-side merging otherwise). N=1 fresh
            // learns skip it — their pure-Swift merge is instant, extraction-done IS completion.
            let consolidationSpec: [String: Any]? = (refineBase != nil || n > 1)
                ? StyleConsolidator.consolidationSpec(
                    newCount: n,
                    baseSources: refineBase.map { $0.sources.isEmpty ? [$0.profile] : $0.sources } ?? [],
                    knownSignatures: refineBase.map { Self.confirmedQuotes(of: $0) } ?? [],
                    suppressed: refineBase?.suppressed ?? [])
                : nil
            let ordered: [(Int, String)] = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (i, clip) in clips.enumerated() {
                    group.addTask { [weak self] in
                        // Compress this single video to a 720p proxy (first 60% of its progress slice).
                        let proxy = try await VideoPreprocessor.mergeAndCompress(clips: [clip]) { p in
                            Task { @MainActor in self?.setClipProgress(i, p * 0.6) }
                        }
                        await MainActor.run { self?.noteClipCompressed() }   // stage → .uploading once ALL are done
                        try Task.checkCancellation()
                        // Upload phone→Google (background-task assertion covers a tap-away mid-upload),
                        // then hand the extraction to the server.
                        let uploaded = try await BackgroundActivity.run("style-upload") {
                            try await GeminiService.shared.upload(at: proxy.url)
                        }
                        await MainActor.run { self?.setClipProgress(i, 0.9) }
                        let jobId = try await GeminiService.shared.startStyleExtractionJob(
                            fileURI: uploaded.fileURI, fileName: uploaded.fileName, mimeType: uploaded.mimeType,
                            prompt: GeminiPrompt.styleProfile,
                            schema: StyleConsolidator.extractionSchema,
                            batchId: batchId, batchSize: n,
                            batchIndex: i, consolidation: consolidationSpec)
                        await MainActor.run { self?.setClipProgress(i, 1.0) }
                        return (i, jobId)
                    }
                }
                var out: [(Int, String)] = []
                for try await pair in group { out.append(pair) }
                return out.sorted { $0.0 < $1.0 }   // deterministic job order = clip order
            }
            if Task.isCancelled { return }
            let jobIds = ordered.map(\.1)
            jobStarted = true   // from here a timeout means "still running server-side", not a hard failure
            stage = .watching   // all jobs handed off — the work is server-side now; canLeave flips true HERE
            progress = 0.5

            // Persist ALL jobs so a kill mid-poll can recover the whole submission on relaunch — mirrors
            // the edit pipeline's `AnalysisJobStore.save`. Multi-video learns resume every job, then
            // re-consolidate (the consolidation call is cheap + idempotent, so it just re-runs).
            if Task.isCancelled { return }
            StyleJobStore.save(jobIds: jobIds, origin: origin, clipSignature: signature ?? "",
                               poster: posterImage, clipCount: clips.count,
                               refineTemplateId: refineBase?.id)

            // Phase B (50 → 95%) — poll each job to completion. The work runs server-side, so a
            // suspend/resume just continues polling (no lost progress).
            var profiles: [StyleProfileRaw] = []
            for (i, jobId) in jobIds.enumerated() {
                if Task.isCancelled { return }
                let base = 0.5 + 0.45 * Double(i) / Double(n)
                let span = 0.45 / Double(n)
                label = n > 1 ? "Reading video \(i + 1) of \(n)" : "Reading your style"

                let raw = try await GeminiService.shared.awaitJobResult(jobId: jobId) { [weak self] _ in
                    Task { @MainActor in self?.progress = min(base + span * 0.9, 0.95) }
                }
                if Task.isCancelled { return }

                Log.blob(.gemini, "RAW STYLE PROFILE (video \(i + 1)/\(n))", raw)
                let profile = try StyleProfileRaw.parse(fromRawModelText: raw)
                // Viability gate: the style call runs with NO response schema, so ANY JSON object — even {} —
                // decodes into an all-defaults profile. Reject an empty one so it takes the failure path
                // instead of shipping a blank "My style" template that poisons future edit prompts.
                guard !(profile.styleBrief.isEmpty && profile.confidence == 0) else {
                    throw EditPlanParseError.decodeFailed("style profile came back empty")
                }
                // v2-prompt soft check: an otherwise-viable profile missing ALL three new blocks means the
                // template silently falls back to derived (generic) habits — flag it loudly, don't fail.
                if profile.verbalStyle.isEmpty && profile.habitCandidates.isEmpty && profile.revealScript.isEmpty {
                    Log.gemini("⚠️ Extraction returned no verbal_style / habit_candidates / reveal_script — template will use derived-habit fallback.")
                }
                profiles.append(profile)
                analyzedCount = i + 1
                progress = base + span
            }

            // Phase C (95 → 100%) — N=1 keeps the pure-Swift merge; N≥2 consolidates with a model call
            // (semantic dedupe + per-item evidence); a REFINE re-consolidates the base's sources + the new
            // profiles and merges back through TemplateRefiner. `consolidate` never throws (merge fallback).
            if Task.isCancelled { return }
            stage = .synthesizing
            label = refineBase != nil ? "Finding what held up"
                  : (profiles.count > 1 ? "Finding what repeats" : "Putting your style into words")
            progress = 0.98

            // The merge normally already ran (or is running) SERVER-side — the proxy chained it when the
            // last extraction landed. Await that result; nil (N=1 / old server / chain failure) falls
            // back to the on-device call inside `buildTemplate`, exactly the old path.
            let chainedRaw = consolidationSpec != nil ? await fetchChainedConsolidation(jobIds: jobIds) : nil
            if Task.isCancelled { return }
            let built = await buildTemplate(from: profiles, clipCount: clips.count, chainedRaw: chainedRaw)
            if Task.isCancelled { return }
            Log.blob(.gemini, "DECODED STYLE TEMPLATE", built.debugSummary)

            template = built
            progress = 1.0
            phase = .done
            // NB: we deliberately DON'T clear StyleJobStore here. The record now lives until the template is
            // durably SAVED (review → Save, or onboarding's saveAndEnter), so a kill/jetsam during review
            // re-offers the paid result on next launch instead of losing it. Cleared in the save/cancel
            // handlers and at the top of `launch()`. Mirrors AnalysisCoordinator.ship()'s persist-first order.
            // Persist the FINISHED result too, so that re-offer restores straight to the review — without
            // this, every relaunch mid-review re-entered Analyzing and re-ran the consolidation model call.
            StyleJobStore.saveBuilt(built, diff: diff)
            //
            // The server pushes "your style is ready" (a closed-phone APNs alert, same path as the edit
            // flow's "cut is ready"). Only post a LOCAL notification as a fallback when there's no APNs
            // token to push to, so the two never double.
            if NotificationService.shared.deviceTokenHex == nil {
                NotificationService.shared.notify(
                    title: "Your style is ready ✨",
                    body: "“\(built.name)” — learned from \(clips.count) video\(clips.count == 1 ? "" : "s"). Tap to review.",
                    screen: "template"
                )
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            handlePipelineError(error, jobStarted: jobStarted)
        }
    }

    /// Phase C, shared by `run` and `resumePipeline`: fresh learns merge (N=1) or consolidate (N≥2);
    /// refinements re-consolidate the base's sources + the new profiles (confirmed quotes pinned as KNOWN
    /// SIGNATURES, rejections as REJECTED LINES) and merge back through `TemplateRefiner` so user edits
    /// survive. Sets `diff` for the mini-reveal on the refine path.
    /// `chainedRaw` = the SERVER-chained consolidation result when the proxy already ran the merge (the
    /// normal path now — same prompt, authored client-side at submit); it goes through the same code-side
    /// trust layer (`decodeConsolidated`). nil or a bad decode falls back to the on-device call.
    private func buildTemplate(from profiles: [StyleProfileRaw], clipCount: Int,
                               chainedRaw: String? = nil) async -> StyleTemplate {
        func decodeChained(sources: [StyleProfileRaw], suppressed: [String]) -> StyleProfileRaw? {
            guard let chainedRaw else { return nil }
            do {
                let merged = try StyleConsolidator.decodeConsolidated(fromRawModelText: chainedRaw,
                                                                      sources: sources, suppressed: suppressed)
                Log.gemini("Using server-chained consolidation (\(sources.count) sources).")
                return merged
            } catch {
                Log.gemini("⚠️ Chained consolidation didn't decode (\(error.localizedDescription)) — re-running on-device.")
                return nil
            }
        }
        if let base = refineBase {
            let baseSources = base.sources.isEmpty ? [base.profile] : base.sources
            let all = baseSources + profiles
            let merged: StyleProfileRaw
            if let chained = decodeChained(sources: all, suppressed: base.suppressed) {
                merged = chained
            } else {
                merged = await StyleConsolidator.consolidate(all,
                                                             knownSignatures: Self.confirmedQuotes(of: base),
                                                             suppressed: base.suppressed)
            }
            let (refined, d) = TemplateRefiner.apply(base: base, consolidated: merged, newSources: profiles)
            diff = d
            Log.gemini("Refined “\(base.name)”: \(d.summaryLine)")
            return refined
        }
        let merged: StyleProfileRaw
        if profiles.count > 1 {
            if let chained = decodeChained(sources: profiles, suppressed: []) {
                merged = chained
            } else {
                merged = await StyleConsolidator.consolidate(profiles)
            }
        } else {
            merged = StyleProfileRaw.merge(profiles)
        }
        return StyleTemplate(from: merged, count: clipCount, sources: profiles)
    }

    /// Discover + await the server-chained consolidation job. The latch winner stamps its id on every
    /// batch row within ~a second of the last extraction finishing, so a short discovery window is
    /// enough; nil at any step (pre-chain server, stamp raced, chained job failed) simply hands Phase C
    /// back to the on-device merge. On a kill-resume the chained job usually finished long ago — the
    /// await returns instantly with the stored result.
    private func fetchChainedConsolidation(jobIds: [String]) async -> String? {
        guard let probe = jobIds.last else { return nil }
        var chainedId: String?
        for attempt in 0..<6 {
            if Task.isCancelled { return nil }
            if let id = await GeminiService.shared.consolidationJobId(forJob: probe) { chainedId = id; break }
            if attempt < 5 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        guard let chainedId else {
            Log.gemini("No chained consolidation job surfaced — using the on-device merge.")
            return nil
        }
        do {
            let raw = try await GeminiService.shared.awaitJobResult(jobId: chainedId) { [weak self] _ in
                Task { @MainActor in self?.progress = min(0.995, (self?.progress ?? 0.98) + 0.002) }
            }
            Log.blob(.gemini, "RAW CONSOLIDATED PROFILE (server-chained)", raw)
            return raw
        } catch is CancellationError {
            return nil
        } catch {
            Log.gemini("⚠️ Chained consolidation unavailable (\(error.localizedDescription)) — using the on-device merge.")
            return nil
        }
    }

    /// The quotes the creator locked in — pinned verbatim in the consolidation prompt so paraphrase drift
    /// can't break code-side matching.
    private static func confirmedQuotes(of t: StyleTemplate) -> [String] {
        var out = t.profile.verbalStyle.recurringLines
            .filter { $0.confirmation == "every" && !$0.quote.isEmpty }
            .map { ($0.pattern?.isEmpty == false) ? $0.pattern! : $0.quote }
        if t.profile.verbalStyle.signoffConfirmation == "every", !t.profile.verbalStyle.signoff.isEmpty {
            out.append(t.profile.verbalStyle.signoff)
        }
        return out
    }

    /// Map a pipeline error to the right state + notification, centralizing the "never destroy a recoverable
    /// server job" policy shared by `run` and `resumePipeline`.
    /// - Parameter jobStarted: whether the server extraction job was created before the error. `false` only
    ///   for a pre-job compress/upload failure in `run`; a resume is always post-job, so passes `true`.
    private func handlePipelineError(_ error: Error, jobStarted: Bool) {
        Log.gemini("Style pipeline error: \(error.localizedDescription)")
        // A timeout AFTER the job started just means we stopped waiting — the job is still running
        // server-side. KEEP the recovery record so the next launch / a Retry re-attaches and delivers the
        // paid result. Soft copy, no scary notification.
        if jobStarted, let ge = error as? GeminiError, case .timedOut = ge {
            Log.gemini("Style poll timed out; keeping recovery record for re-attach.")
            phase = .failed("Vela's still working on your style — we'll pick it up next time you open the app, or tap Retry.")
            return
        }
        // A compress killed by backgrounding (iOS suspends the AVFoundation export) gets the humane copy
        // that pairs with the "Open Vela to finish" nudge — not a raw AVFoundation error string.
        if stage == .compressing,
           error.localizedDescription.localizedCaseInsensitiveContains("interrupt")
            || error.localizedDescription.localizedCaseInsensitiveContains("cancel") {
            StyleJobStore.clear()
            phase = .failed("Vela needs to stay open while it preps your footage. Tap Retry to try again.")
            return
        }
        // Everything else is terminal — drop the record.
        StyleJobStore.clear()
        phase = .failed(error.localizedDescription)
        // A server-job failure (.badRequest) means the worker already pushed "hit a snag" to a closed app —
        // only add a local ping when there's no token for that push (so they don't double). ANY other error
        // (client-side parse/viability failure of a job the server thinks SUCCEEDED, or a pre-job failure the
        // server never knew about) has no server push at all, so ALWAYS ping locally, else it's silent.
        let serverPushedFailure: Bool = { if let ge = error as? GeminiError, case .badRequest = ge { return true }; return false }()
        if !serverPushedFailure || NotificationService.shared.deviceTokenHex == nil {
            NotificationService.shared.notify(title: "Style analysis hit a snag",
                                              body: error.localizedDescription, screen: "template")
        }
    }

    // MARK: - Kill recovery (full app termination, not just backgrounding)

    /// Re-attach to a persisted style job after the app was killed mid-learn and finish it. Idempotent:
    /// no-ops unless we're `.idle` with a saved pending job of THIS coordinator's `origin`, so it never
    /// disturbs a live run or a loaded result, and onboarding vs. create never resume each other. The job
    /// already ran server-side, so this only polls + builds the template (no re-upload, no re-pay). Returns
    /// `true` when it actually kicked off a resume — so `RootView` / `OnboardingView` can route to review.
    @discardableResult
    func resumeIfPending() -> Bool {
        guard phase == .idle, let pending = StyleJobStore.load(), pending.origin == origin else { return false }
        // Bound the deleted-row case: a 404 from `status` is retried as a transient blip → 300s timeout →
        // record kept → would re-poll a long-gone job on every launch. Abandon anything older than 7 days.
        if Date().timeIntervalSince(pending.createdAt) > 7 * 24 * 3600 {
            Log.gemini("Abandoning stale pending style job \(pending.jobId) (>7d old).")
            StyleJobStore.clear()
            return false
        }
        // A refine resume must reload its base template — if it was deleted meanwhile, abandon gracefully
        // (the extraction result has no home to merge into).
        if origin == .refine {
            guard let baseId = pending.refineTemplateId,
                  let base = FileTemplateStore.shared.list().first(where: { $0.id == baseId }) else {
                Log.gemini("Abandoning pending refine — its base template is gone.")
                StyleJobStore.clear()
                return false
            }
            refineBase = base
        }
        // The analysis already FINISHED before the kill (killed/rebuilt mid-review) → restore the built
        // result instantly instead of re-entering Analyzing. The old path re-polled every done job and
        // re-ran the consolidation model call on EVERY launch until the template was saved — and showed
        // a blank-tiled "Vela is watching" screen doing it. `.done` + template flow through the existing
        // routing (AnalyzingStepView fires onDone immediately; RootView's phase observers route the
        // create/refine flows), so the user lands straight on the Reveal/review.
        if let built = StyleJobStore.loadBuilt() {
            Log.gemini("Restoring built style template from \(pending.jobId) — skipping re-analysis.")
            signature = pending.clipSignature
            totalCount = pending.clipCount
            analyzedCount = pending.clipCount
            posterImage = StyleJobStore.loadPoster(pending)
            compressedCount = 0
            progress = 1.0
            stage = .synthesizing
            label = "Picking up where you left off"
            template = built.template
            diff = built.diff
            phase = .done             // synchronous flip → observers route to review, can't double-resume
            return true
        }
        Log.gemini("Resuming pending style job \(pending.jobId) after relaunch.")
        signature = pending.clipSignature
        totalCount = pending.clipCount
        analyzedCount = 0
        posterImage = StyleJobStore.loadPoster(pending)   // restore the tile thumbnail lost with the clips
        phase = .running          // synchronous flip → can't double-resume
        stage = .watching         // a resume is always post-job — the compress/upload happened pre-kill
        compressedCount = 0
        progress = 0.6
        label = "Reading your style"
        template = nil
        task = Task { [weak self] in
            await self?.resumePipeline(pending: pending)
        }
        return true
    }

    private func resumePipeline(pending: PendingStyleJob) async {
        Task { await NotificationService.shared.requestAuthorization() }
        do {
            // `awaitJobResult`'s 300s deadline is recomputed fresh here (per job), so a resume after a long
            // background/kill restarts the poll clock — a job that outlived the original window is still
            // recoverable. Multi-video learns resume EVERY persisted job, then re-consolidate (the
            // consolidation call is cheap + idempotent).
            let ids = pending.allJobIds
            var profiles: [StyleProfileRaw] = []
            for (i, jobId) in ids.enumerated() {
                if Task.isCancelled { return }
                label = ids.count > 1 ? "Reading video \(i + 1) of \(ids.count)" : "Reading your style"
                let raw = try await GeminiService.shared.awaitJobResult(jobId: jobId) { [weak self] _ in
                    Task { @MainActor in self?.progress = min(0.95, (self?.progress ?? 0.6) + 0.01) }
                }
                if Task.isCancelled { return }
                Log.blob(.gemini, "RAW STYLE PROFILE (resumed \(i + 1)/\(ids.count))", raw)
                let profile = try StyleProfileRaw.parse(fromRawModelText: raw)
                guard !(profile.styleBrief.isEmpty && profile.confidence == 0) else {
                    throw EditPlanParseError.decodeFailed("style profile came back empty")
                }
                profiles.append(profile)
                analyzedCount = i + 1
            }
            if Task.isCancelled { return }
            stage = .synthesizing
            label = refineBase != nil ? "Finding what held up"
                  : (profiles.count > 1 ? "Finding what repeats" : "Putting your style into words")
            // A batched learn's merge already ran server-side (that's what pushed "ready") — fetch it;
            // nil falls back to the on-device call inside `buildTemplate` exactly as before.
            let chainedRaw = (refineBase != nil || ids.count > 1) ? await fetchChainedConsolidation(jobIds: ids) : nil
            if Task.isCancelled { return }
            let built = await buildTemplate(from: profiles, clipCount: pending.clipCount, chainedRaw: chainedRaw)
            if Task.isCancelled { return }
            template = built
            analyzedCount = pending.clipCount
            progress = 1.0
            phase = .done
            // Record kept until durable save (see `run`) — no clear here. Persist the built result so the
            // NEXT relaunch skips straight to review instead of re-polling + re-consolidating again.
            StyleJobStore.saveBuilt(built, diff: diff)
            if NotificationService.shared.deviceTokenHex == nil {
                NotificationService.shared.notify(
                    title: "Your style is ready ✨",
                    body: "“\(built.name)” — tap to review.",
                    screen: "template"
                )
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            handlePipelineError(error, jobStarted: true)   // a resume is always post-job
        }
    }
}
