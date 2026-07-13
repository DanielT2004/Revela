import Foundation

/// One placement of a B-roll clip on the overlay layer (Layer 2). It plays **over** the main spine
/// for `[startOnBase, startOnBase + duration]` (assembled main-timeline seconds), supplying only
/// VIDEO — the base track's audio (the creator's voice) keeps playing underneath.
///
/// This is the generalized form of the legacy `EditPlanStore.brollSource` map: instead of a B-roll
/// being locked 1:1 to a voiceover slot, it can sit anywhere on the timeline and be freely dragged,
/// trimmed, added, or removed on the Polish page. The same lane drives both the live preview
/// (`PolishComposition`) and the final export (`EditPlanAssembler`), so what you see is what you get.
struct OverlayClip: Identifiable, Equatable, Codable {
    /// Sentinel for a not-yet-resolved `sourceStart` — an old project decoded before this field existed, or a
    /// caller that let it default. `EditPlanStore` normalizes any negative value to the source segment's own
    /// `startSeconds` on load (head-anchored — the legacy behavior), so migration is invisible.
    static let unsetSourceStart: Double = -1

    let id: UUID
    /// The B-roll source segment (∈ `EditPlanStore.brollClips`) whose video fills this window.
    var sourceSegmentId: Int
    /// Where the overlay begins along the assembled main timeline, in seconds.
    var startOnBase: Double
    /// How long it covers, in seconds. Clamped ≤ the source segment's length, so each window maps to
    /// a single contiguous source slice (no looping needed).
    var duration: Double
    /// Absolute **proxy** seconds where this overlay's source slice begins — the overlay's in-point (the
    /// parallel of `Clip.inPoint` on the spine). Left-trim advances this so the LATER source content plays;
    /// without it, trimming the left edge could only drop tail content. Seeded to the segment's `startSeconds`.
    var sourceStart: Double
    /// Overlay audio volume, 0…1. Defaults to **0** (muted) — B-roll plays silently over the voice;
    /// raise it to mix the B-roll's own sound in.
    var volume: Float

    init(id: UUID = UUID(), sourceSegmentId: Int, startOnBase: Double, duration: Double,
         sourceStart: Double = OverlayClip.unsetSourceStart, volume: Float = 0) {
        self.id = id
        self.sourceSegmentId = sourceSegmentId
        self.startOnBase = startOnBase
        self.duration = duration
        self.sourceStart = sourceStart
        self.volume = volume
    }

    private enum CodingKeys: String, CodingKey { case id, sourceSegmentId, startOnBase, duration, sourceStart, volume }

    /// Custom decode so projects saved before `sourceStart` existed still load — an absent field becomes the
    /// sentinel, which `EditPlanStore` resolves to the segment start on load (unchanged, head-anchored render).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceSegmentId = try c.decode(Int.self, forKey: .sourceSegmentId)
        startOnBase = try c.decode(Double.self, forKey: .startOnBase)
        duration = try c.decode(Double.self, forKey: .duration)
        sourceStart = (try? c.decode(Double.self, forKey: .sourceStart)) ?? OverlayClip.unsetSourceStart
        volume = try c.decode(Float.self, forKey: .volume)
    }

    /// Exclusive end on the assembled main timeline.
    var endOnBase: Double { startOnBase + duration }
}
