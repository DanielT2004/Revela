import Foundation
import Observation
import UIKit

/// Owns the *current* project's identity and upserts it to the `ProjectStore`. Injected into the
/// environment (alongside `VideoSession`) so any screen can trigger a save, and `RootView` saves on
/// backgrounding / when the user leaves the editor. Resume adopts an existing project so edits update
/// it in place rather than creating a duplicate.
@Observable
final class ProjectService {
    private let store: ProjectStore

    private(set) var currentId: UUID?
    private(set) var currentStatus: ProjectStatus = .triage
    private var createdAt = Date()
    private(set) var name = "Untitled cut"

    /// The durable proxy location for the current project (where `save` persists the ~720p proxy). Lets a
    /// resumed session repoint off its ephemeral PendingAnalysis copy onto this stable file.
    var currentProxyURL: URL? { currentId.map { store.proxyURL(for: $0) } }

    /// Where the current project's voiceover takes are recorded to (survives app kill; deleted with the
    /// project). Nil only before a project exists — the Polish page falls back to a temp dir then.
    var narrationDirectory: URL? { currentId.map { store.narrationDirectory(for: $0) } }

    init(store: ProjectStore = FileProjectStore.shared) { self.store = store }

    /// Saved projects for the Home grid (newest-edited first).
    func allProjects() -> [Project] { store.list() }

    /// In-memory cache of decoded Home-tile posters, keyed by project id. `NSCache` is thread-safe and
    /// evicts under memory pressure. Keeps the project list from re-reading + re-decoding poster JPEGs from
    /// disk on the main thread every layout pass (the cause of the ~1–2s scroll stall on returning to Home).
    private let posterCache = NSCache<NSString, UIImage>()

    /// A poster already decoded in memory — instant, no disk. Nil on a cold cache; the row shows its gradient
    /// placeholder until `loadPoster` fills it.
    func cachedPoster(for id: UUID) -> UIImage? { posterCache.object(forKey: id.uuidString as NSString) }

    /// Read + decode a project's Home-tile poster OFF the main thread and cache it. Returns nil when the
    /// project has no poster. Mirrors `ThumbnailService`'s async+cache pattern used for clip thumbnails.
    func loadPoster(for id: UUID) async -> UIImage? {
        let key = id.uuidString as NSString
        if let hit = posterCache.object(forKey: key) { return hit }
        guard let url = store.posterURL(for: id) else { return nil }
        let image = await Self.decodePoster(at: url)
        if let image { posterCache.setObject(image, forKey: key) }
        return image
    }

    /// Load the JPEG and force its decode on a background thread, so the first on-screen draw doesn't hitch.
    private static func decodePoster(at url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
            return await img.byPreparingForDisplay() ?? img
        }.value
    }

    func delete(_ id: UUID) {
        posterCache.removeObject(forKey: id.uuidString as NSString)
        try? store.delete(id: id)
    }

    // MARK: - Lifecycle

    /// Track a freshly-analyzed session as a brand-new project.
    func startNew(from plan: EditPlan) {
        currentId = UUID()
        createdAt = Date()
        currentStatus = .triage
        name = Self.deriveName(plan)
    }

    /// Adopt an existing project on resume so further saves update it in place.
    func adopt(_ project: Project) {
        currentId = project.id
        createdAt = project.createdAt
        name = project.name
        currentStatus = project.status
    }

    /// Forget the active project (e.g. when starting a brand-new video from Home).
    func clearCurrent() { currentId = nil }

    /// Load a saved project and rehydrate the session so the editor resumes off the saved proxy.
    /// Returns the screen to route to (based on how far the project got), or nil on failure.
    /// Full-resolution export re-resolution from the camera roll is added in CP1.4; for now the
    /// session carries a proxy-identity span so editing and a proxy export work with no asset access.
    @MainActor
    func resume(_ project: Project, into session: VideoSession) async -> AppScreen? {
        guard let loaded = try? store.load(id: project.id) else {
            Log.app("⚠️ Couldn't load project \(project.name).")
            return nil
        }
        let proxyURL = loaded.proxyURL
        let meta = await VideoInspector.metadata(for: proxyURL)
            ?? VideoMetadata(duration: loaded.meta.durationSeconds, width: 1080, height: 1920, fileSizeBytes: 0)
        let proxySpan = SourceSpan(url: proxyURL, assetIdentifier: nil, startInMerged: 0, duration: meta.duration)

        session.startFresh()
        session.merged = ProcessedVideo(url: proxyURL, metadata: meta, inputBytes: 0, elapsed: 0, sourceSpans: [proxySpan])
        session.store = EditPlanStore(plan: loaded.plan, restoring: loaded.state)
        session.originSources = loaded.sources   // for full-res re-resolution at export (CP1.4)
        // Point the restored narration takes at this project's narration/ dir and drop any whose file
        // vanished (the lane persists names only). The count surfaces once as a Polish toast.
        session.store?.narrationDirectory = store.narrationDirectory(for: project.id)
        if let dropped = session.store?.pruneMissingNarration(), dropped > 0 {
            session.store?.prunedNarrationOnResume = dropped
        }
        adopt(loaded.meta)
        Log.app("📂 Resumed \(loaded.meta.name) [\(loaded.meta.status.rawValue)] — \(loaded.state.order.count) clips.")

        // Resume into the editor shell at the stage matching how far the project got. Set the
        // high-water mark first so the StageSwitcher shows the right ✓ marks (editorStage's didSet only
        // ever raises furthestStage, so this order is safe).
        switch loaded.meta.status {
        case .triage:
            session.editorStage = .sort
        case .polishing, .exported:
            session.furthestStage = .polish
            session.editorStage = .arrange
        }
        return .editor
    }

    // MARK: - Save

    /// Upsert the current session under its tracked project id. `reaching` only ever *upgrades* the
    /// status (triage → polishing → exported), never downgrades.
    func save(session: VideoSession, reaching status: ProjectStatus? = nil, poster: UIImage? = nil) {
        guard let id = currentId, let model = session.store, let merged = session.merged else { return }
        if let status, status.rank > currentStatus.rank { currentStatus = status }

        let sources = merged.sourceSpans.map {
            PersistedSpan(assetIdentifier: $0.assetIdentifier, startInMerged: $0.startInMerged, duration: $0.duration)
        }
        let meta = Project(id: id, name: name, createdAt: createdAt, editedAt: Date(),
                           status: currentStatus,
                           clipCount: model.order.count + model.brollClips.count,
                           durationSeconds: model.totalDuration,
                           schemaVersion: Project.currentSchema)
        let doc = ProjectDocument(meta: meta, plan: model.plan, state: model.snapshot(), sources: sources)
        do { try store.save(doc, copyingProxyFrom: merged.url, poster: poster) }
        catch { Log.app("⚠️ Project save failed: \(error.localizedDescription)") }
    }

    // MARK: - Rename + feedback

    /// Rename the current project and persist immediately. Trimmed; an empty or unchanged name is a no-op.
    /// `name` is the single source of truth (written into `project.json` by `save`), so the editor header
    /// and the Home tile both reflect it. Returns true when the rename was committed.
    @discardableResult
    func rename(to newName: String, session: VideoSession) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return false }
        name = trimmed
        save(session: session)   // metadata-only save — `reaching` nil, so status can't downgrade
        Log.app("✏️ Renamed project → “\(trimmed)”.")
        return true
    }

    /// Persist the export "did this feel like you?" verdict durably (survives kill / re-open) so the future
    /// style-learning loop has real signal. Mutates the live store, then saves.
    func recordExportFeedback(_ verdict: Bool, session: VideoSession) {
        session.store?.exportFeedback = verdict
        save(session: session)
        Log.app("👍 Export feedback saved: \(verdict ? "loved it" : "not quite").")
    }

    // MARK: - Helpers

    /// A short, friendly title derived from the AI's one-line summary (used until the user renames).
    private static func deriveName(_ plan: EditPlan) -> String {
        let s = plan.videoSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "Untitled cut" }
        let words = s.split(separator: " ").prefix(5).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
