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

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var label = "Getting started"
    private(set) var analyzedCount = 0        // videos finished (drives the mockup's "{n} of {N}" counter)
    private(set) var totalCount = 0
    private(set) var template: StyleTemplate?
    /// First clip's frame — saved as the template's library-tile thumbnail.
    private(set) var posterImage: UIImage?

    private var signature: String?
    private var task: Task<Void, Never>?

    // MARK: entry points

    func start(clips: [SourceClip]) {
        let sig = AnalysisCoordinator.signature(for: clips)
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
        launch(clips: clips, signature: AnalysisCoordinator.signature(for: clips))
    }

    private func launch(clips: [SourceClip], signature sig: String) {
        signature = sig
        phase = .running
        progress = 0
        analyzedCount = 0
        totalCount = clips.count
        label = "Getting started"
        template = nil
        // Wrap in a background-task assertion so analysis keeps running (and notifies) if the creator
        // backgrounds the app mid-call.
        task = Task { [weak self] in
            await BackgroundActivity.run("style-analysis") { await self?.run(clips: clips) }
        }
    }

    // MARK: pipeline — one extraction per video, then merge

    private func run(clips: [SourceClip]) async {
        Task { await NotificationService.shared.requestAuthorization() }
        guard !clips.isEmpty else { phase = .failed("No videos to learn from."); return }
        posterImage = clips.first?.thumbnail   // tile thumbnail for the saved template

        do {
            var profiles: [StyleProfileRaw] = []
            let n = clips.count
            for (i, clip) in clips.enumerated() {
                if Task.isCancelled { return }
                let base = Double(i) / Double(n)
                let span = 1.0 / Double(n)
                label = n > 1 ? "Watching video \(i + 1) of \(n)" : "Watching your video"

                // Compress this single video to a 720p proxy (first 30% of its slice).
                let proxy = try await VideoPreprocessor.mergeAndCompress(clips: [clip]) { [weak self] p in
                    Task { @MainActor in self?.progress = base + span * (p * 0.30) }
                }
                if Task.isCancelled { return }

                // Extract the style profile (next 65% of its slice).
                let raw = try await GeminiService.shared.rawStyleTemplateJSON(forVideoAt: proxy.url) { [weak self] stage, frac in
                    Task { @MainActor in
                        self?.progress = base + span * (0.30 + frac * 0.65)
                        if n == 1 { self?.label = stage }
                    }
                }
                if Task.isCancelled { return }

                Log.blob(.gemini, "RAW STYLE PROFILE (video \(i + 1)/\(n))", raw)
                profiles.append(try StyleProfileRaw.parse(fromRawModelText: raw))
                analyzedCount = i + 1
                progress = base + span
            }

            if Task.isCancelled { return }
            label = "Putting your style into words"
            progress = 0.98

            let merged = StyleProfileRaw.merge(profiles)
            let built = StyleTemplate(from: merged, count: clips.count)
            Log.blob(.gemini, "DECODED STYLE TEMPLATE", built.debugSummary)

            template = built
            progress = 1.0
            phase = .done
            NotificationService.shared.notify(
                title: "Your style is ready ✨",
                body: "“\(built.name)” — learned from \(clips.count) video\(clips.count == 1 ? "" : "s"). Tap to review."
            )
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            Log.gemini("Style pipeline error: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            NotificationService.shared.notify(title: "Style analysis hit a snag", body: error.localizedDescription)
        }
    }
}
