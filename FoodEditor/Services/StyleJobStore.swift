import Foundation
import UIKit

/// Which flow owns a pending style-learn job, so the right coordinator/UI re-attaches on relaunch:
/// `onboarding` resumes inside `OnboardingView` (its own step machine); `newTemplate` resumes in
/// `RootView` and routes through the Reveal; `refine` resumes in `RootView` and routes to the
/// mini-reveal (reloading its base template by `refineTemplateId`). See
/// `StyleAnalysisCoordinator.resumeIfPending` — origin gating keeps the three resumers uncrossed.
enum StyleJobOrigin: String, Codable { case onboarding, newTemplate, refine }

/// The persisted record of the ONE in-flight style-extraction job, so learning a style survives the app
/// being **killed** (not just backgrounded) — the same kill-recovery `AnalysisJobStore` gives the edit
/// pipeline. The job already runs server-side; resume only needs to *poll* it and build the template, so
/// we store the `jobId`, the clip signature (dedup on resubmit), the `clipCount` (feeds
/// `StyleTemplate(from:count:)` — the picked clips are gone after a kill), and a durable copy of the
/// poster thumbnail (the only visual artifact the resumed template needs — far lighter than the edit
/// flow's durable proxy, since a style learn never touches the video again).
struct PendingStyleJob: Codable {
    let jobId: String                 // first job (legacy field — old records carry only this)
    let origin: StyleJobOrigin
    let clipSignature: String
    let posterPath: String?
    let clipCount: Int
    let createdAt: Date
    /// ALL extraction jobs for a multi-video learn (nil on legacy single-job records).
    let jobIds: [String]?
    /// When this learn REFINES an existing template (M6), its id — so resume can reload the base.
    let refineTemplateId: UUID?

    var allJobIds: [String] { jobIds ?? [jobId] }
}

/// Tiny Application-Support store for the pending style job (mirrors `AnalysisJobStore`). At most one
/// pending style job exists — onboarding and the create flow each learn one submission at a time, and
/// `origin` keeps their resumers from crossing wires. A **separate** directory from `AnalysisJobStore`'s
/// `PendingAnalysis/`, so an in-flight edit and an in-flight style-learn recover independently.
enum StyleJobStore {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingStyle", isDirectory: true)
    }
    private static var recordURL: URL { dir.appendingPathComponent("pending.json") }

    /// Persist the poster JPEG (if any) to a durable location and write the pending record. Best-effort:
    /// on failure the live run still completes normally, we just can't recover from a kill.
    /// `jobIds` = every extraction job of the submission (one per video); the legacy `jobId` field keeps
    /// the first so an older build reading the record still resumes *something*.
    static func save(jobIds: [String], origin: StyleJobOrigin, clipSignature: String,
                     poster: UIImage?, clipCount: Int, refineTemplateId: UUID? = nil) {
        guard let first = jobIds.first else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var posterPath: String?
            if let data = poster?.jpegData(compressionQuality: 0.7) {
                let durable = dir.appendingPathComponent("poster-\(first).jpg")
                try? data.write(to: durable, options: .atomic)
                posterPath = durable.path
            }
            let rec = PendingStyleJob(jobId: first, origin: origin, clipSignature: clipSignature,
                                      posterPath: posterPath, clipCount: clipCount, createdAt: Date(),
                                      jobIds: jobIds, refineTemplateId: refineTemplateId)
            try JSONEncoder().encode(rec).write(to: recordURL, options: .atomic)
            Log.app("📌 Pending style job saved (\(jobIds.count) job\(jobIds.count == 1 ? "" : "s"), \(origin.rawValue)\(refineTemplateId != nil ? ", refine" : "")).")
        } catch {
            Log.app("⚠️ Pending-style-job save failed: \(error.localizedDescription)")
        }
    }

    static func load() -> PendingStyleJob? {
        guard let data = try? Data(contentsOf: recordURL) else { return nil }
        return try? JSONDecoder().decode(PendingStyleJob.self, from: data)
    }

    /// Reload the persisted poster thumbnail for a resumed job (nil → the template tile falls back to a
    /// gradient mini-grid, which `TemplateService.poster(for:)` already tolerates).
    static func loadPoster(_ rec: PendingStyleJob) -> UIImage? {
        guard let path = rec.posterPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return UIImage(data: data)
    }

    /// Drop the record + its durable poster (call once the template is durably saved/discarded or the job
    /// genuinely failed).
    static func clear() {
        if let rec = load(), let path = rec.posterPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        try? FileManager.default.removeItem(at: recordURL)
        try? FileManager.default.removeItem(at: revealURL)
        try? FileManager.default.removeItem(at: builtURL)
    }

    // MARK: - Built-result sidecar (skip re-analysis on relaunch)

    /// The FINISHED template (+ refine diff), written the moment Phase C completes. Without it, a relaunch
    /// mid-review re-entered the Analyzing screen (blank tiles — the clips died with the kill), re-polled
    /// every done job, and — the real cost — re-ran the N≥2 consolidation MODEL CALL on every launch until
    /// the template was durably saved. With it, `resumeIfPending` restores straight to `.done` and the
    /// existing routing lands on the Reveal/review instantly. Rides the record's lifecycle: `clear()`
    /// drops it, and `launch()`'s clear supersedes it before any fresh paid run.
    struct BuiltStyleResult: Codable {
        let template: StyleTemplate
        let diff: TemplateDiff?      // refine flow only — restores the mini-reveal's story
    }
    private static var builtURL: URL { dir.appendingPathComponent("built.json") }

    static func saveBuilt(_ template: StyleTemplate, diff: TemplateDiff? = nil) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(BuiltStyleResult(template: template, diff: diff)) {
            try? data.write(to: builtURL, options: .atomic)
            Log.app("📌 Built style template persisted (resume will skip re-analysis).")
        }
    }

    static func loadBuilt() -> BuiltStyleResult? {
        guard let data = try? Data(contentsOf: builtURL) else { return nil }
        return try? JSONDecoder().decode(BuiltStyleResult.self, from: data)
    }

    // MARK: - Reveal progress sidecar (kill-durable confirmations)

    /// The Reveal's answers feel transactional (flash + haptic), so they must BE durable: every card
    /// answer writes here incrementally; a kill mid-Reveal resumes at the first unanswered card with the
    /// story skipped. Keyed by the signature's normalized key ("__rating__"/"__signoff__" for the two
    /// scalars); values are the verdicts ("every" | "sometimes" | "out"). Rides the same directory
    /// lifecycle as the pending record — `clear()` (durable save / discard) drops it too.
    struct RevealProgress: Codable {
        var storyCompleted = false
        var answers: [String: String] = [:]
    }
    private static var revealURL: URL { dir.appendingPathComponent("reveal.json") }

    static func saveRevealProgress(_ progress: RevealProgress) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(progress) {
            try? data.write(to: revealURL, options: .atomic)
        }
    }

    static func loadRevealProgress() -> RevealProgress? {
        guard let data = try? Data(contentsOf: revealURL) else { return nil }
        return try? JSONDecoder().decode(RevealProgress.self, from: data)
    }
}
