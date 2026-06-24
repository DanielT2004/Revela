import Foundation
import Observation

/// Appends camera-roll clips to an EXISTING edit (post-analysis) **without** re-running Gemini. Adding
/// clips means rebuilding the single merged proxy; because new clips are appended at the END, every
/// existing clip keeps its exact proxy timestamps, so all current edits (order, trims, B-roll, text)
/// stay valid. The new clips land as plain synthetic segments on the spine for the creator to edit by
/// hand.
///
/// Deliberately separate from `AnalysisCoordinator` (whose whole contract is "run the paid Gemini call
/// exactly once") so this lightweight re-merge can never trigger analysis. Owns the async merge +
/// progress so the work survives the Polish view churning, mirroring the coordinator pattern.
@MainActor
@Observable
final class ClipImportCoordinator {
    enum Phase: Equatable { case idle, merging, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    var isBusy: Bool { phase == .merging }

    /// Re-merge with the freshly-picked clips appended, then graft them onto the store's spine. The
    /// caller pushes undo before calling (so the whole import is one undo step) and refreshes the
    /// preview/thumbnails afterward.
    func importClips(_ picked: [PickedClip], into session: VideoSession) async {
        guard let store = session.store, !picked.isEmpty else { return }
        let oldProxyDuration = session.merged?.metadata.duration ?? 0

        // 1) Ingest into the session (appends SourceClips + kicks off async metadata/thumbnail loads).
        session.ingest(picked)
        // 2) Readiness gate — wait until the newly-appended clips have metadata so we know their assets
        //    are loadable. (mergeAndCompress re-reads each asset's duration itself; this isn't the source.)
        await waitForMetadata(session: session, count: picked.count)

        phase = .merging
        progress = 0
        Log.video("Importing \(picked.count) clip(s) into the current edit (no re-analysis)…")
        do {
            // 3) Re-merge ALL clips (existing + new) into a fresh proxy.
            let processed = try await VideoPreprocessor.mergeAndCompress(clips: session.clips) { [weak self] p in
                Task { @MainActor in self?.progress = p }
            }

            // 4) Spans at/after the OLD proxy duration are the appended clips (new clips are at the end).
            let newSpans = processed.sourceSpans.filter { $0.startInMerged >= oldProxyDuration - 0.05 }

            // 5) One synthetic Segment per new span, ids above every existing segment.
            var nextId = store.nextSegmentId
            let newSegments: [Segment] = newSpans.map { span in
                let seg = Segment.imported(id: nextId,
                                           startSeconds: span.startInMerged,
                                           endSeconds: span.startInMerged + span.duration)
                nextId += 1
                return seg
            }

            // 6) Commit on the main actor: swap the proxy, then graft the new clips onto the spine.
            session.merged = processed
            store.appendImportedSegments(newSegments)
            Log.video("Imported \(newSegments.count) clip(s); spine now \(store.order.count) clip(s).")

            phase = .idle
            progress = 0
        } catch {
            Log.video("Clip import failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Poll (≈5s max) until the last `count` clips have loaded metadata.
    private func waitForMetadata(session: VideoSession, count: Int) async {
        for _ in 0..<50 {
            let tail = session.clips.suffix(count)
            if tail.count >= count && tail.allSatisfy({ $0.metadata != nil }) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
