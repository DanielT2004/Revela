import Foundation
import Observation
import UIKit

/// Owns the one-shot **merge + Gemini analysis** pipeline for a session. The pipeline used to live in
/// `ProcessingView.run()`, where it was triggered by the view's `.task` — but a SwiftUI view's mount /
/// remount lifecycle is fragile (RootView's `.id(router.screen)` recreates the view, resetting its
/// `@State`), so a remount could re-fire the **paid** Gemini call. This coordinator moves ownership out
/// of the view into a stable `@Observable` injected from `RootView` (same pattern as `ProjectService`).
///
/// **Exactly-once guarantee.** `start(session:projects:)` is idempotent and safe to call on every
/// `ProcessingView` appearance:
///   • `phase` flips to `.running` **synchronously, before the first `await`** — two near-simultaneous
///     mounts can't both launch (closes the in-flight concurrency window the old guard missed).
///   • idempotency is keyed to a **signature of the submitted clip set**, so re-entering with the same
///     clips no-ops, while a genuinely new submission runs once.
///   • the in-flight `Task` is held **here, not in the view**, so the analysis survives `ProcessingView`
///     disappearing — the user can navigate away or background the app mid-call and it still finishes
///     once and fires the completion notification.
/// The only intentional re-trigger is the user tapping **Retry** on the error state (`retry(...)`).
@MainActor
@Observable
final class AnalysisCoordinator {
    enum Phase: Equatable {
        case idle
        case running
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var label = "Getting started"
    private(set) var rawResponse: String?

    /// Identity of the clip set we are / finished analyzing — the key for "run once per submission."
    private var signature: String?
    /// The owned pipeline task. Lives here (not in the View) so analysis survives the view disappearing.
    private var task: Task<Void, Never>?
    /// The active style's injection block (M7), or "" for a generic edit. Set at launch.
    private var styleBlock = ""
    /// The per-video Pre-Edit Brief block, or "" if no brief. Prepended after the style block. Set at launch.
    private var briefBlock = ""
    /// The active template's B-roll coverage target (fraction 0…1), threaded into the store's seeding cap.
    private var brollCoverageTarget = 0.25

    // MARK: - Entry points

    /// Idempotent. `ProcessingView` calls this from its `.task`, which may fire on every (re)mount.
    /// `styleBlock` carries the active template's Style Injection Block (M7), or "" for a generic edit.
    func start(session: VideoSession, projects: ProjectService, styleBlock: String = "", briefBlock: String = "", brollCoverageTarget: Double = 0.25) {
        let sig = Self.signature(for: session.clips)
        switch phase {
        case .running:
            return                                                  // a call is already in flight
        case .done where signature == sig && session.store != nil:
            return                                                  // same clips, result still loaded
        case .failed where signature == sig:
            return                                                  // wait for an explicit Retry
        default:
            break                                                   // .idle / new clips / stale .done
        }
        launch(session: session, projects: projects, signature: sig, styleBlock: styleBlock, briefBlock: briefBlock, brollCoverageTarget: brollCoverageTarget)
    }

    /// The one intentional re-trigger — user tapped Retry on the error state.
    func retry(session: VideoSession, projects: ProjectService, styleBlock: String = "", briefBlock: String = "", brollCoverageTarget: Double = 0.25) {
        task?.cancel()
        launch(session: session, projects: projects, signature: Self.signature(for: session.clips), styleBlock: styleBlock, briefBlock: briefBlock, brollCoverageTarget: brollCoverageTarget)
    }

    // MARK: - Pipeline

    private func launch(session: VideoSession, projects: ProjectService, signature sig: String, styleBlock: String, briefBlock: String, brollCoverageTarget: Double) {
        signature = sig
        self.styleBlock = styleBlock
        self.briefBlock = briefBlock
        self.brollCoverageTarget = brollCoverageTarget
        phase = .running            // flipped synchronously, before any await → no double-launch
        progress = 0
        label = "Getting started"
        rawResponse = nil
        task = Task { [weak self] in
            await self?.runPipeline(session: session, projects: projects)
        }
    }

    private func runPipeline(session: VideoSession, projects: ProjectService) async {
        // Ask for notification permission up front (non-blocking) so we can ping when done.
        Task { await NotificationService.shared.requestAuthorization() }
        do {
            // Phase 1 — merge + compress (0 → 30%). Reuse an existing merge (e.g. a retry) if present.
            let processed: ProcessedVideo
            if let existing = session.merged {
                processed = existing
            } else {
                processed = try await VideoPreprocessor.mergeAndCompress(clips: session.clips) { [weak self] p in
                    Task { @MainActor in
                        self?.progress = p * 0.30
                        self?.label = "Stitching your clips"
                    }
                }
                session.merged = processed
            }

            // Phase 2 — upload phone→Google (30 → 55%). Wrapped in a background-task assertion so a
            // tap-away mid-upload can still finish in the iOS grace window.
            label = "Uploading your video"; progress = 0.32
            let uploaded = try await BackgroundActivity.run("vela-upload") {
                try await GeminiService.shared.upload(at: processed.url)
            }
            if Task.isCancelled { return }
            progress = 0.55

            // Phase 3 — hand the analysis off to the server (55 → 60%). From here the work runs on
            // Supabase (poll + generate), so the user can CLOSE THE APP and it still finishes.
            label = "Analyzing on the server"; progress = 0.58
            let prompt = styleBlock + briefBlock + GeminiPrompt.editPlan
            let jobId = try await GeminiService.shared.startAnalysisJob(
                fileURI: uploaded.fileURI, fileName: uploaded.fileName, mimeType: uploaded.mimeType, prompt: prompt)

            // Phase 4 — poll the job until done/failed (60 → 95%). The SERVER does the work; if the app
            // is backgrounded here, nothing is lost — the poll just resumes when we're foreground again.
            let raw = try await pollUntilFinished(jobId: jobId)

            // A newer launch (Retry) may have superseded us — don't clobber its result.
            if Task.isCancelled { return }

            // Phase 5 — parse + finalize (95 → 100%).
            try await finalize(raw: raw, processed: processed, session: session, projects: projects)
        } catch is CancellationError {
            return                                                  // superseded — leave newer state intact
        } catch {
            if Task.isCancelled { return }
            Log.gemini("Pipeline error: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            NotificationService.shared.notify(
                title: "Analysis hit a snag",
                body: error.localizedDescription
            )
        }
    }

    /// Polls the server job until it finishes. The work runs server-side, so a dropped poll (e.g. the
    /// app was suspended mid-request) is harmless — we swallow transient network errors and try the next
    /// tick. Throws only on a genuine job failure, cancellation, or the overall timeout.
    private func pollUntilFinished(jobId: String) async throws -> String {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                switch try await GeminiService.shared.jobStatus(jobId: jobId) {
                case .done(let raw):
                    return raw
                case .failed(let why):
                    throw GeminiError.badRequest(why)               // genuine job failure — surface it
                case .active(let stage):
                    label = stage
                    progress = min(0.95, max(progress, 0.6) + 0.015)   // gentle creep so the arc keeps moving
                }
            } catch let e as GeminiError {
                if case .badRequest = e { throw e }                 // job-level failure → fatal
                Log.gemini("Status poll blip (will retry): \(e.localizedDescription)")   // HTTP blip → transient
            } catch is CancellationError {
                throw CancellationError()                           // superseded / torn down — propagate
            } catch {
                Log.gemini("Status poll blip (will retry): \(error.localizedDescription)")   // e.g. -1005 after a suspend
            }
            try await Task.sleep(nanoseconds: 2_500_000_000)
        }
        throw GeminiError.timedOut("server job didn't finish in time")
    }

    /// The tail of the pipeline: parse the model JSON into an Edit Plan, install it as the session's
    /// store, mark done, register + save the project, notify, and capture a Home-tile poster. Behaviour
    /// is unchanged from the old on-device flow — only how we *got* `raw` changed (a server job).
    private func finalize(raw: String, processed: ProcessedVideo,
                          session: VideoSession, projects: ProjectService) async throws {
        label = "Putting it together"; progress = 0.97
        let parsed = try EditPlan.parse(fromRawModelText: raw)
        Log.blob(.gemini, "DECODED EDIT PLAN", parsed.debugSummary)

        session.store = EditPlanStore(plan: parsed, brollCoverageTarget: brollCoverageTarget)
        rawResponse = raw
        progress = 1.0
        phase = .done
        // CP1.2 — register this analyzed session as a saved project.
        projects.startNew(from: parsed)
        projects.save(session: session, reaching: .triage)

        NotificationService.shared.notify(
            title: "Your cut is ready 🍴",
            body: "\(parsed.segments.count) moments found · ~\(Int(parsed.recommendedDuration))s suggested. Tap to refine."
        )

        // CP1.3 — capture a Home-tile poster from the proxy's opening frame, then re-save with it.
        let posterTime = parsed.segments.first(where: { $0.id == parsed.finalEditOrder.first })?.startSeconds ?? 0.5
        if let poster = await ThumbnailService.thumbnail(for: processed.url, at: posterTime) {
            projects.save(session: session, poster: poster)
        }
    }

    // MARK: - Clip-set identity

    /// Order- and count-sensitive identity of the submitted clips (reordering or adding a clip is a new
    /// submission → a new analysis). Prefers the photo-library asset id, falls back to the temp file path.
    static func signature(for clips: [SourceClip]) -> String {
        clips.map { $0.assetIdentifier ?? $0.url.path }.joined(separator: "|")
    }
}
