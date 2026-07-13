import Foundation
import Observation
import UIKit

/// Owns the creator's saved style templates + which one is active. Injected into the environment (like
/// `ProjectService`) so any screen can read the active style or switch it. The active template steers new
/// edits in M7.
@Observable
final class TemplateService {
    private var store: TemplateStore

    private(set) var templates: [StyleTemplate] = []
    private(set) var activeId: UUID?
    /// A mutable working copy bound by the editor when re-opening an existing template (M5.5).
    var editingDraft: StyleTemplate?

    init(store: TemplateStore = FileTemplateStore.shared) {
        self.store = store
        reload()
    }

    var active: StyleTemplate? { templates.first { $0.id == activeId } }
    var isEmpty: Bool { templates.isEmpty }

    /// The saved tile thumbnail for a template (nil → cards fall back to a gradient mini-grid).
    func poster(for id: UUID) -> UIImage? { store.posterImage(for: id) }

    /// Begin editing an existing template — stashes a working copy the editor binds to.
    func beginEditing(_ template: StyleTemplate) { editingDraft = template }

    func reload() {
        templates = store.list()
        activeId = store.activeId
        // Heal a dangling/absent active id: default to the newest template.
        if active == nil { setActive(templates.first?.id) }
    }

    /// Upsert a template. The first template ever saved becomes active automatically. Pass `poster` only
    /// when there's a fresh thumbnail to write (analysis) — editing an existing template passes nil to keep it.
    func save(_ template: StyleTemplate, poster: UIImage? = nil) {
        // Any template touched by this build persists at the current schema (older builds gate at their
        // own version and skip it — that's the gate's purpose; the fields all decode defensively).
        var t = template
        t.schemaVersion = max(t.schemaVersion, StyleTemplate.currentSchemaVersion)
        do { try store.save(t, poster: poster) }
        catch { Log.app("⚠️ Template save failed: \(error.localizedDescription)"); return }
        let wasFirst = templates.isEmpty
        if let idx = templates.firstIndex(where: { $0.id == t.id }) {
            templates[idx] = t
        } else {
            templates.insert(t, at: 0)
        }
        templates.sort { $0.createdAt > $1.createdAt }
        if wasFirst || activeId == nil { setActive(t.id) }
    }

    func setActive(_ id: UUID?) {
        activeId = id
        store.activeId = id
        if let id { Log.app("🍳 Active style → \(templates.first { $0.id == id }?.name ?? "—")") }
    }

    func delete(_ id: UUID) {
        try? store.delete(id: id)
        templates.removeAll { $0.id == id }
        if activeId == id { setActive(templates.first?.id) }
    }

    #if DEBUG
    func deleteAll() {
        (store as? FileTemplateStore)?.deleteAll()
        templates = []
        activeId = nil
    }
    #endif
}
