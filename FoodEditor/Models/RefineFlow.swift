import Foundation
import Observation

/// State for the "sharpen this style" flow — adding 1–2 more videos to an EXISTING template so its
/// signatures can be confirmed across sources. Mirrors `CreateFlow`'s shape (own session so it never
/// clobbers an in-progress edit; own coordinator with its own kill-recovery origin), but re-consolidates
/// over the base template's persisted sources and lands in a diff-driven mini-reveal instead of a fresh
/// template review. Injected from `RootView` so it survives screen swaps.
@MainActor
@Observable
final class RefineFlow {
    let session = VideoSession()
    let coordinator = StyleAnalysisCoordinator(origin: .refine)
    var baseId: UUID?
    var updatedDraft: StyleTemplate?

    var clips: [SourceClip] { session.clips }

    /// Kick off a refinement: ingest the newly-picked videos and start extraction against the base.
    func begin(base: StyleTemplate, picked: [PickedClip]) {
        session.startFresh()
        session.ingest(picked)
        baseId = base.id
        updatedDraft = nil
        coordinator.start(clips: session.clips, refining: base)
    }

    func reset() {
        session.startFresh()
        baseId = nil
        updatedDraft = nil
        coordinator.reset()
    }
}
