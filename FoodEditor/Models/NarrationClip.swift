import Foundation

/// One recorded **voiceover take** on the narration lane. UI copy says "Voiceover"; code says
/// *narration* to avoid colliding with the pipeline's existing "voiceover" (in-footage speech kept
/// under B-roll — `voiceover_candidate` etc.). Unlike footage audio (`AudioPiece`, whose source range
/// is in **proxy** seconds and gets re-mapped to the originals at export), a take is recorded against
/// the assembled timeline itself: file range `[inPoint, outPoint]` plays at `startOnBase` identically
/// in the preview and the export — no proxy mapping, no speed scaling. Timeline-anchored like
/// `OverlayClip`: spine edits don't ripple it; it's only clamped to stay inside the timeline.
struct NarrationClip: Identifiable, Equatable, Codable {
    let id: UUID
    /// File inside the project's `narration/` directory. A name, never an absolute URL — the app
    /// container path changes between installs; `EditPlanStore.narrationDirectory` resolves it.
    var fileName: String
    /// Where the take begins on the assembled main timeline, in seconds.
    var startOnBase: Double
    /// Trim window into the recorded file, in file-local seconds (`inPoint < outPoint`).
    var inPoint: Double
    var outPoint: Double
    /// Full recorded length — clamps trims without loading the asset.
    var fileDuration: Double
    /// Take volume, 0…1. NOT scaled by the master original-audio gain (the voice leads the mix).
    var volume: Float

    init(id: UUID = UUID(), fileName: String, startOnBase: Double,
         inPoint: Double = 0, outPoint: Double, fileDuration: Double, volume: Float = 1) {
        self.id = id
        self.fileName = fileName
        self.startOnBase = startOnBase
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.fileDuration = fileDuration
        self.volume = volume
    }

    var duration: Double { outPoint - inPoint }
    /// Exclusive end on the assembled main timeline.
    var endOnBase: Double { startOnBase + duration }
}

/// A resolved, render-ready narration slice (the file exists on disk). Consumed by BOTH compositors —
/// `PolishComposition` (preview) and `EditPlanAssembler` (export) — so what you hear is what you get.
struct NarrationPiece: Equatable {
    let url: URL
    let startOnBase: Double
    let fileIn: Double
    let fileOut: Double
    let volume: Float
}
