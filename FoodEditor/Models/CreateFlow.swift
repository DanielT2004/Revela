import Foundation
import Observation

/// State for the "create a new template" flow (mockup steps 7–9 + review). Kept **separate** from the
/// editing `VideoSession` so learning a new style never clobbers an in-progress video edit. Owns its own
/// session (reusing `VideoSession.ingest` for metadata/thumbnails), the multi-select set, the analysis
/// coordinator, and the resulting draft. Injected from `RootView` so it survives the create screens
/// remounting as the router swaps them.
@MainActor
@Observable
final class CreateFlow {
    let session = VideoSession()
    var selectedIDs: Set<UUID> = []
    let coordinator = StyleAnalysisCoordinator()
    var draft: StyleTemplate?

    var clips: [SourceClip] { session.clips }
    var selectedClips: [SourceClip] { session.clips.filter { selectedIDs.contains($0.id) } }
    var selectedCount: Int { selectedIDs.count }

    /// Begin a fresh upload-based create.
    func startUpload() { session.startFresh(); selectedIDs = []; draft = nil }

    /// Ingest freshly-picked clips and select all of them by default.
    func ingest(_ picked: [PickedClip]) {
        session.ingest(picked)
        selectedIDs = Set(session.clips.map(\.id))
    }

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func reset() { session.startFresh(); selectedIDs = []; draft = nil }
}
