import Foundation
import UIKit

enum TemplateStoreError: LocalizedError {
    case encodeFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed(let m): return "Couldn't save the template: \(m)"
        case .decodeFailed(let m): return "Couldn't open the template: \(m)"
        }
    }
}

/// Persists learned style templates. Abstracted (like `ProjectStore`) so a future cloud sync is a drop-in.
protocol TemplateStore {
    /// All saved templates, newest first. Never throws — unreadable/incompatible files are skipped.
    func list() -> [StyleTemplate]
    /// Write the template; if `poster` is non-nil, (re)write its tile thumbnail, else leave any existing one.
    func save(_ template: StyleTemplate, poster: UIImage?) throws
    /// The saved tile thumbnail for a template, if one was written.
    func posterImage(for id: UUID) -> UIImage?
    func delete(id: UUID) throws
    /// The active template id (persisted across launches), or nil.
    var activeId: UUID? { get set }
}

/// Local, file-based store: one folder per template under Application Support.
/// `Templates/<uuid>/{template.json, poster.jpg}`. Active id lives in `UserDefaults`. No network, no database.
final class FileTemplateStore: TemplateStore {
    static let shared = FileTemplateStore()
    static let activeIdKey = "vela.activeTemplateId"

    private let root: URL
    private let fm = FileManager.default

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    init(rootOverride: URL? = nil) {
        if let rootOverride {
            root = rootOverride
        } else {
            let appSupport = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                           in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            root = appSupport.appendingPathComponent("Templates", isDirectory: true)
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func docURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("template.json") }
    private func posterURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("poster.jpg") }

    func list() -> [StyleTemplate] {
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let templates: [StyleTemplate] = entries.compactMap { dir in
            guard dir.hasDirectoryPath,
                  let id = UUID(uuidString: dir.lastPathComponent),
                  let data = try? Data(contentsOf: docURL(id)),
                  let t = try? decoder.decode(StyleTemplate.self, from: data),
                  t.schemaVersion <= 2
            else { return nil }
            return t
        }
        return templates.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ template: StyleTemplate, poster: UIImage?) throws {
        try fm.createDirectory(at: folder(template.id), withIntermediateDirectories: true)
        if let poster, let jpeg = poster.jpegData(compressionQuality: 0.7) {
            try? jpeg.write(to: posterURL(template.id))
        }
        do {
            let data = try encoder.encode(template)
            try data.write(to: docURL(template.id), options: .atomic)
        } catch {
            throw TemplateStoreError.encodeFailed(error.localizedDescription)
        }
        Log.app("💾 Saved template \"\(template.name)\" → \(folder(template.id).lastPathComponent)")
    }

    func posterImage(for id: UUID) -> UIImage? {
        let url = posterURL(id)
        guard fm.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func delete(id: UUID) throws {
        try? fm.removeItem(at: folder(id))
        if activeId == id { activeId = nil }
    }

    var activeId: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: Self.activeIdKey) else { return nil }
            return UUID(uuidString: s)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.activeIdKey) }
    }

    #if DEBUG
    func deleteAll() {
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        activeId = nil
        Log.app("🍳 Deleted all templates (DEBUG).")
    }

    static func runSelfTest() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tmpl-selftest-\(UUID().uuidString)")
        let store = FileTemplateStore(rootOverride: tmp)
        store.save(silently: StyleTemplate.sample)
        let back = store.list()
        if back.count == 1, back.first?.name == StyleTemplate.sample.name {
            Log.app("🍳 TemplateStore self-test round-trip OK.")
        } else {
            Log.app("⚠️ TemplateStore self-test MISMATCH (\(back.count) found).")
        }
        try? FileManager.default.removeItem(at: tmp)
    }

    private func save(silently template: StyleTemplate) { try? save(template, poster: nil) }
    #endif
}
