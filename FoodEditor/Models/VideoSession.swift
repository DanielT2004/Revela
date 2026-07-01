import Foundation
import UIKit
import Observation

/// One selected source clip from the camera roll (copied to a temp file we own). Metadata and a
/// first-frame thumbnail load asynchronously after selection.
struct SourceClip: Identifiable {
    let id = UUID()
    let url: URL
    /// The photo-library local identifier (when available) — used to preselect/dedup in "Add more".
    var assetIdentifier: String? = nil
    var metadata: VideoMetadata? = nil
    var thumbnail: UIImage? = nil
}

/// Holds the state for one editing session as it flows through the pipeline. Creators can select
/// MULTIPLE clips (e.g. several recordings to stitch); they're concatenated in order downstream
/// (M2) so everything after still operates on a single video timeline.
@Observable
final class VideoSession {
    /// The selected source clips, in the order they'll be stitched.
    var clips: [SourceClip] = []

    /// The clips concatenated + compressed into one 720p file (M2) — the video sent to Gemini.
    var merged: ProcessedVideo?

    /// The parsed analysis result + editable state (M4) — the single source of truth for editing.
    var store: EditPlanStore?

    /// The required per-video brief the creator confirmed before processing (`BriefView`). Becomes the
    /// prepended brief prompt block in the Gemini call. `nil` until the brief screen submits.
    var brief: EditBrief?

    /// Which editor stage is on screen (Sort/Arrange/Polish). Lives on the session (not view `@State`)
    /// so it survives `RootView`'s `.id(router.screen)` remount when returning from Export/Hook — the
    /// `EditorShellView` reads it to pick which content view to mount. Setting it auto-advances the
    /// high-water mark below, which drives the ✓ "completed" marks in the `StageSwitcher`.
    var editorStage: EditorStage = .sort {
        didSet { if editorStage.index > furthestStage.index { furthestStage = editorStage } }
    }
    /// The furthest stage reached so far (only ever advances). Drives the switcher's ✓ marks.
    var furthestStage: EditorStage = .sort

    /// One-shot "a fresh analysis just landed" flag. Set when routing to the results screen after
    /// completion (RootView); consumed + cleared by `FirstCutView.onAppear` to show the celebratory
    /// reveal curtain exactly once (never on Back-from-editor, which re-reads it already false).
    var pendingReveal: Bool = false

    /// On a RESUMED project, the persisted source map (proxy-timeline → original PHAsset). Lets export
    /// re-resolve full-resolution originals from the camera roll. `nil` for a fresh session (whose
    /// `merged.sourceSpans` still point at on-disk temp originals). See `ExportSourceResolver`.
    var originSources: [PersistedSpan]?

    var count: Int { clips.count }
    var isEmpty: Bool { clips.isEmpty }

    /// Photo-library identifiers of the current selection — fed back to the picker so already-added
    /// clips show as selected ("Add more" won't create duplicates).
    var selectedAssetIdentifiers: [String] { clips.compactMap { $0.assetIdentifier } }

    /// Combined duration of all clips with known metadata (seconds).
    var totalDuration: Double { clips.reduce(0) { $0 + ($1.metadata?.duration ?? 0) } }

    var totalDurationText: String {
        let t = Int(totalDuration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Combined file size of all clips with known metadata.
    var totalSizeText: String {
        let bytes = clips.reduce(Int64(0)) { $0 + ($1.metadata?.fileSizeBytes ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: mutations

    func add(_ clip: SourceClip) { clips.append(clip) }

    func remove(atOffsets offsets: IndexSet) { clips.remove(atOffsets: offsets) }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }

    func updateDetails(id: UUID, metadata: VideoMetadata?, thumbnail: UIImage?) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        if let metadata { clips[idx].metadata = metadata }
        if let thumbnail { clips[idx].thumbnail = thumbnail }
    }

    // MARK: ingesting picked clips (shared by PickerView + onboarding Connect)

    /// Append freshly-picked clips and kick off async metadata + thumbnail loading for each.
    func ingest(_ picked: [PickedClip]) {
        guard !picked.isEmpty else { return }
        Log.video("Adding \(picked.count) clip(s) to the session…")
        for p in picked {
            let clip = SourceClip(url: p.url, assetIdentifier: p.assetIdentifier)
            add(clip)
            Task { await loadDetails(clipID: clip.id, url: p.url) }
        }
    }

    private func loadDetails(clipID: UUID, url: URL) async {
        async let metaTask = VideoInspector.metadata(for: url)
        async let thumbTask = ThumbnailService.thumbnail(for: url)
        let meta = await metaTask
        let thumb = await thumbTask
        await MainActor.run {
            updateDetails(id: clipID, metadata: meta, thumbnail: thumb)
            if let meta, let idx = clips.firstIndex(where: { $0.id == clipID }) {
                Log.video("""
                Clip \(idx + 1) — \(url.lastPathComponent): \(meta.durationText) \
                (\(String(format: "%.1f", meta.duration))s), \(meta.resolutionText) \
                (\(meta.isPortrait ? "portrait" : "landscape")), \(meta.fileSizeText)
                """)
            }
            Log.video("Session total: \(count) clip(s), \(totalDurationText), \(totalSizeText).")
        }
    }

    func reset() { clips.removeAll(); originSources = nil; brief = nil }

    /// Fully clear the session for a brand-new project (or before loading a saved one).
    func startFresh() {
        clips.removeAll()
        merged = nil
        store = nil
        brief = nil
        originSources = nil
        furthestStage = .sort
        editorStage = .sort
        pendingReveal = false
    }
}
