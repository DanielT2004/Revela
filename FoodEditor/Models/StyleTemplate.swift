import Foundation

// ============================================================================
// MARK: - StyleProfileRaw — the exact JSON the extraction prompt (call 1) returns
// ============================================================================
//
// Mirrors GeminiPrompt.styleProfile's schema 1:1 (snake_case keys). Decoded defensively: a bad/missing
// sub-object falls back to its default rather than failing the whole parse. One of these is produced per
// analyzed video; several are merged (StyleProfileRaw.merge) into the profile a template is built from.

struct SignatureMove: Codable, Equatable {
    var move: String = ""
    var likelyHabit: Double = 0
    enum CodingKeys: String, CodingKey { case move; case likelyHabit = "likely_habit" }
    init(move: String = "", likelyHabit: Double = 0) { self.move = move; self.likelyHabit = likelyHabit }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        move = (try? c.decode(String.self, forKey: .move)) ?? ""
        likelyHabit = try c.lenientDouble(.likelyHabit) ?? 0
    }
}

struct VideoFormatInfo: Codable, Equatable {
    var type = ""; var typeCustom: String? = nil; var notes = ""
    enum CodingKeys: String, CodingKey { case type; case typeCustom = "type_custom"; case notes }
}

struct HookInfo: Codable, Equatable {
    var type = ""; var typeCustom: String? = nil
    var opensWithinSeconds: Double = 0
    var hasTextOverlay = false
    var description = ""
    enum CodingKeys: String, CodingKey {
        case type; case typeCustom = "type_custom"
        case opensWithinSeconds = "opens_within_seconds"
        case hasTextOverlay = "has_text_overlay"; case description
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        typeCustom = try? c.decodeIfPresent(String.self, forKey: .typeCustom)
        opensWithinSeconds = try c.lenientDouble(.opensWithinSeconds) ?? 0
        hasTextOverlay = (try? c.decode(Bool.self, forKey: .hasTextOverlay)) ?? false
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }
    /// The base value, or the free-text description when the model said "other".
    var resolved: String { if type == "other" || type.isEmpty, let cu = typeCustom, !cu.isEmpty { return cu }; return type }
}

struct PacingInfo: Codable, Equatable {
    var totalLengthSeconds: Double = 0
    var averageClipLengthSeconds: Double = 0
    var cutStyle = ""; var cutStyleCustom: String? = nil
    var pacingNotes = ""
    enum CodingKeys: String, CodingKey {
        case totalLengthSeconds = "total_length_seconds"
        case averageClipLengthSeconds = "average_clip_length_seconds"
        case cutStyle = "cut_style"; case cutStyleCustom = "cut_style_custom"
        case pacingNotes = "pacing_notes"
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        totalLengthSeconds = try c.lenientDouble(.totalLengthSeconds) ?? 0
        averageClipLengthSeconds = try c.lenientDouble(.averageClipLengthSeconds) ?? 0
        cutStyle = (try? c.decode(String.self, forKey: .cutStyle)) ?? ""
        cutStyleCustom = try? c.decodeIfPresent(String.self, forKey: .cutStyleCustom)
        pacingNotes = (try? c.decode(String.self, forKey: .pacingNotes)) ?? ""
    }
    var cutStyleResolved: String { if cutStyle == "other" || cutStyle.isEmpty, let cu = cutStyleCustom, !cu.isEmpty { return cu }; return cutStyle }
}

struct VoiceoverInfo: Codable, Equatable {
    var primaryMode = ""; var primaryModeCustom: String? = nil
    var voiceoverRatio: Double = 0
    var talksToCamera = false
    var notes = ""
    enum CodingKeys: String, CodingKey {
        case primaryMode = "primary_mode"; case primaryModeCustom = "primary_mode_custom"
        case voiceoverRatio = "voiceover_ratio"; case talksToCamera = "talks_to_camera"; case notes
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        primaryMode = (try? c.decode(String.self, forKey: .primaryMode)) ?? ""
        primaryModeCustom = try? c.decodeIfPresent(String.self, forKey: .primaryModeCustom)
        voiceoverRatio = try c.lenientDouble(.voiceoverRatio) ?? 0
        talksToCamera = (try? c.decode(Bool.self, forKey: .talksToCamera)) ?? false
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }
}

struct BrollInfo: Codable, Equatable {
    var amount = ""; var usage = ""; var usageCustom: String? = nil
    var favoredShots: [String] = []
    var notes = ""
    /// How much of the final video to auto-cover with B-roll, as a fraction 0…1 (default 25%). The user
    /// owns this in the template editor; it drives both the Gemini coverage target and the seeding cap.
    var heaviness: Double = 0.25
    enum CodingKeys: String, CodingKey {
        case amount, usage; case usageCustom = "usage_custom"
        case favoredShots = "favored_shots"; case notes; case heaviness
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        amount = (try? c.decode(String.self, forKey: .amount)) ?? ""
        usage = (try? c.decode(String.self, forKey: .usage)) ?? ""
        usageCustom = try? c.decodeIfPresent(String.self, forKey: .usageCustom)
        favoredShots = (try? c.decode([String].self, forKey: .favoredShots)) ?? []
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        heaviness = try c.lenientDouble(.heaviness) ?? 0.25
    }
    var usageResolved: String { if usage == "other" || usage.isEmpty, let cu = usageCustom, !cu.isEmpty { return cu }; return usage }
    var favoredShotsText: String { favoredShots.isEmpty ? "any strong food shots" : favoredShots.joined(separator: ", ") }
}

/// One named beat inside a section (e.g. "introduce restaurant"). `id` is local SwiftUI identity, never
/// decoded from Gemini (synthesized fresh — see StyleHabit). `core` is computed in `merge` (the beat
/// appears in EVERY analyzed example) and DOES persist, so the brief can pre-check the consistent beats.
struct SectionBeat: Codable, Equatable, Identifiable {
    var id = UUID()
    var label = ""
    var timeHint = ""
    var core = false
    enum CodingKeys: String, CodingKey { case label; case timeHint = "time_hint"; case core }
    init(id: UUID = UUID(), label: String = "", timeHint: String = "", core: Bool = false) {
        self.id = id; self.label = label; self.timeHint = timeHint; self.core = core
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        timeHint = (try? c.decode(String.self, forKey: .timeHint)) ?? ""
        core = (try? c.decode(Bool.self, forKey: .core)) ?? false
    }
}

/// One narrative section (intro / middle / end) and the named beats this creator includes in it. `id` is
/// local SwiftUI identity, never decoded.
struct StyleSection: Codable, Equatable, Identifiable {
    var id = UUID()
    var section = ""            // "intro" | "middle" | "end"
    var purpose = ""
    var beats: [SectionBeat] = []
    enum CodingKeys: String, CodingKey { case section, purpose, beats }
    init(id: UUID = UUID(), section: String = "", purpose: String = "", beats: [SectionBeat] = []) {
        self.id = id; self.section = section; self.purpose = purpose; self.beats = beats
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        section = (try? c.decode(String.self, forKey: .section)) ?? ""
        purpose = (try? c.decode(String.self, forKey: .purpose)) ?? ""
        beats = (try? c.decode([SectionBeat].self, forKey: .beats)) ?? []
    }
}

struct StructureInfo: Codable, Equatable {
    var arc: [String] = []
    var notes = ""
    var sections: [StyleSection] = []   // learned intro/middle/end breakdown (schema 2+); empty for legacy
    init() {}
    init(arc: [String], notes: String = "", sections: [StyleSection] = []) { self.arc = arc; self.notes = notes; self.sections = sections }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        arc = (try? c.decode([String].self, forKey: .arc)) ?? []
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        sections = (try? c.decode([StyleSection].self, forKey: .sections)) ?? []
    }
    enum CodingKeys: String, CodingKey { case arc, notes, sections }
    var arcText: String { arc.isEmpty ? "hook → build → payoff → close" : arc.joined(separator: " → ") }
}

struct TextGraphicsInfo: Codable, Equatable {
    var usesTextOverlays = false
    var textStyle = ""; var textStyleCustom: String? = nil
    var amount = ""
    enum CodingKeys: String, CodingKey {
        case usesTextOverlays = "uses_text_overlays"
        case textStyle = "text_style"; case textStyleCustom = "text_style_custom"; case amount
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        usesTextOverlays = (try? c.decode(Bool.self, forKey: .usesTextOverlays)) ?? false
        textStyle = (try? c.decode(String.self, forKey: .textStyle)) ?? ""
        textStyleCustom = try? c.decodeIfPresent(String.self, forKey: .textStyleCustom)
        amount = (try? c.decode(String.self, forKey: .amount)) ?? ""
    }
    var textStyleResolved: String { if textStyle == "other" || textStyle.isEmpty, let cu = textStyleCustom, !cu.isEmpty { return cu }; return textStyle }
}

struct AudioInfo: Codable, Equatable {
    var bed = ""; var bedCustom: String? = nil
    var keepsNaturalFoodSounds = false
    var notes = ""
    enum CodingKeys: String, CodingKey {
        case bed; case bedCustom = "bed_custom"
        case keepsNaturalFoodSounds = "keeps_natural_food_sounds"; case notes
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        bed = (try? c.decode(String.self, forKey: .bed)) ?? ""
        bedCustom = try? c.decodeIfPresent(String.self, forKey: .bedCustom)
        keepsNaturalFoodSounds = (try? c.decode(Bool.self, forKey: .keepsNaturalFoodSounds)) ?? false
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }
}

struct ClosingInfo: Codable, Equatable {
    var type = ""; var typeCustom: String? = nil
    var description = ""
    enum CodingKeys: String, CodingKey { case type; case typeCustom = "type_custom"; case description }
    init() {}
    init(type: String, typeCustom: String? = nil, description: String = "") {
        self.type = type; self.typeCustom = typeCustom; self.description = description
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        typeCustom = try? c.decodeIfPresent(String.self, forKey: .typeCustom)
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }
    var resolved: String { if type == "other" || type.isEmpty, let cu = typeCustom, !cu.isEmpty { return cu }; return type }
}

/// The full reverse-engineered style profile for one (or merged across several) finished video(s).
struct StyleProfileRaw: Codable, Equatable {
    var styleBrief = ""
    var videoFormat = VideoFormatInfo()
    var hook = HookInfo()
    var pacing = PacingInfo()
    var voiceover = VoiceoverInfo()
    var broll = BrollInfo()
    var structure = StructureInfo()
    var textAndGraphics = TextGraphicsInfo()
    var audio = AudioInfo()
    var closing = ClosingInfo()
    var signatureMoves: [SignatureMove] = []
    var anythingUnusual: String? = nil
    var sceneTypesPresent: [String] = []
    var confidence: Double = 0

    enum CodingKeys: String, CodingKey {
        case styleBrief = "style_brief"
        case videoFormat = "video_format"
        case hook, pacing
        case voiceover = "voiceover_vs_oncamera"
        case broll, structure
        case textAndGraphics = "text_and_graphics"
        case audio, closing
        case signatureMoves = "signature_moves"
        case anythingUnusual = "anything_unusual"
        case sceneTypesPresent = "scene_types_present"
        case confidence
    }

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        styleBrief      = (try? c.decode(String.self, forKey: .styleBrief)) ?? ""
        videoFormat     = (try? c.decode(VideoFormatInfo.self, forKey: .videoFormat)) ?? VideoFormatInfo()
        hook            = (try? c.decode(HookInfo.self, forKey: .hook)) ?? HookInfo()
        pacing          = (try? c.decode(PacingInfo.self, forKey: .pacing)) ?? PacingInfo()
        voiceover       = (try? c.decode(VoiceoverInfo.self, forKey: .voiceover)) ?? VoiceoverInfo()
        broll           = (try? c.decode(BrollInfo.self, forKey: .broll)) ?? BrollInfo()
        structure       = (try? c.decode(StructureInfo.self, forKey: .structure)) ?? StructureInfo()
        textAndGraphics = (try? c.decode(TextGraphicsInfo.self, forKey: .textAndGraphics)) ?? TextGraphicsInfo()
        audio           = (try? c.decode(AudioInfo.self, forKey: .audio)) ?? AudioInfo()
        closing         = (try? c.decode(ClosingInfo.self, forKey: .closing)) ?? ClosingInfo()
        signatureMoves  = (try? c.decode([SignatureMove].self, forKey: .signatureMoves)) ?? []
        anythingUnusual = try? c.decodeIfPresent(String.self, forKey: .anythingUnusual)
        sceneTypesPresent = (try? c.decode([String].self, forKey: .sceneTypesPresent)) ?? []
        confidence      = try c.lenientDouble(.confidence) ?? 0
    }

    /// Parse raw model text (fence-tolerant) into a profile.
    static func parse(fromRawModelText raw: String) throws -> StyleProfileRaw {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
            if let close = s.range(of: "```", options: .backwards) { s = String(s[..<close.lowerBound]) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end,
              let data = String(s[start...end]).data(using: .utf8) else { throw EditPlanParseError.noJSONObject }
        do { return try JSONDecoder().decode(StyleProfileRaw.self, from: data) }
        catch { throw EditPlanParseError.decodeFailed(error.localizedDescription) }
    }

    /// Merge several per-video profiles into one. Categorical fields come from the most-confident video
    /// (coherent), numbers are averaged, lists are unioned/topped. Single-element input returns itself.
    static func merge(_ profiles: [StyleProfileRaw]) -> StyleProfileRaw {
        guard var merged = profiles.max(by: { $0.confidence < $1.confidence }) else { return StyleProfileRaw() }
        // Sections: union the named beats per canonical section across every example, ordered by how many
        // examples include them, and mark a beat `core` when it appears in ALL of them (→ pre-checked on the
        // brief). Runs for any count — a single example trivially makes every beat core.
        merged.structure.sections = mergeSections(profiles)
        guard profiles.count > 1 else { return merged }

        func avg(_ f: (StyleProfileRaw) -> Double) -> Double {
            let xs = profiles.map(f).filter { $0 > 0 }
            return xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
        }
        merged.hook.opensWithinSeconds      = avg { $0.hook.opensWithinSeconds }
        merged.pacing.totalLengthSeconds    = avg { $0.pacing.totalLengthSeconds }
        merged.pacing.averageClipLengthSeconds = avg { $0.pacing.averageClipLengthSeconds }
        merged.voiceover.voiceoverRatio     = avg { $0.voiceover.voiceoverRatio }
        merged.confidence                   = avg { $0.confidence }

        // Favored shots: most frequent across videos, top 3.
        var shotCounts: [String: Int] = [:]
        for p in profiles { for s in p.broll.favoredShots { shotCounts[s, default: 0] += 1 } }
        merged.broll.favoredShots = shotCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        // Signature moves: dedupe by text, keep highest likely_habit, top 4.
        var moves: [String: SignatureMove] = [:]
        for p in profiles { for m in p.signatureMoves {
            let k = m.move.lowercased()
            if let e = moves[k], e.likelyHabit >= m.likelyHabit { continue }
            moves[k] = m
        } }
        merged.signatureMoves = moves.values.sorted { $0.likelyHabit > $1.likelyHabit }.prefix(4).map { $0 }

        merged.sceneTypesPresent = Array(Set(profiles.flatMap { $0.sceneTypesPresent })).sorted()
        let unusual = profiles.compactMap { $0.anythingUnusual }.filter { !$0.isEmpty && $0.lowercased() != "null" }
        merged.anythingUnusual = unusual.isEmpty ? nil : Array(Set(unusual)).joined(separator: "; ")
        return merged
    }

    /// Merge the learned intro/middle/end sections across examples: for each canonical section, union its
    /// beats by normalized label, order by how many examples include them (most-common first), and mark a
    /// beat `core` when it appears in EVERY example. A single example → every beat is trivially core.
    private static func mergeSections(_ profiles: [StyleProfileRaw]) -> [StyleSection] {
        let n = profiles.count
        return ["intro", "middle", "end"].compactMap { name -> StyleSection? in
            let perProfile = profiles.compactMap { p in
                p.structure.sections.first { $0.section.trimmingCharacters(in: .whitespaces).lowercased() == name }
            }
            guard !perProfile.isEmpty else { return nil }

            var order: [String] = []                       // first-seen order, for deterministic tie-breaks
            var counts: [String: Int] = [:]
            var display: [String: String] = [:]
            var timeHint: [String: String] = [:]
            for sec in perProfile {
                var seenHere = Set<String>()               // count each label at most once per example
                for b in sec.beats {
                    let key = b.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !key.isEmpty, seenHere.insert(key).inserted else { continue }
                    if counts[key] == nil { order.append(key); display[key] = b.label; timeHint[key] = b.timeHint }
                    counts[key, default: 0] += 1
                }
            }
            let beats = order.enumerated()
                .sorted { a, b in
                    let ca = counts[a.element] ?? 0, cb = counts[b.element] ?? 0
                    return ca != cb ? ca > cb : a.offset < b.offset
                }
                .map { (_, key) in
                    SectionBeat(label: display[key] ?? key, timeHint: timeHint[key] ?? "", core: (counts[key] ?? 0) == n)
                }
            let purpose = perProfile.first { !$0.purpose.trimmingCharacters(in: .whitespaces).isEmpty }?.purpose ?? ""
            return StyleSection(section: name, purpose: purpose, beats: beats)
        }
    }
}

// ============================================================================
// MARK: - Editable display surface (mockup step 4)
// ============================================================================

/// One toggle on the profile screen — a fully-owned item the creator can rename / remove / add. Enabled
/// toggles are sent to the AI as "honor this habit" when cutting new videos (M7). `id` is local (SwiftUI
/// identity), never persisted.
struct StyleHabit: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String
    var detail: String? = nil
    var on: Bool = true
    enum CodingKeys: String, CodingKey { case label, detail, on }   // `id` excluded → synthesized fresh
    init(id: UUID = UUID(), label: String, detail: String? = nil, on: Bool = true) {
        self.id = id; self.label = label; self.detail = detail; self.on = on
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        on = (try? c.decode(Bool.self, forKey: .on)) ?? true
    }
}

/// Legacy fixed-shape habits (schemaVersion 1) — kept only so older saved templates migrate to `[StyleHabit]`.
struct StyleHabits: Codable, Equatable {
    var punch = false, jump = false, vo = false, caption = false, ambient = false, beat = false
    enum CodingKeys: String, CodingKey {
        case punch, jump; case vo = "voiceover"; case caption = "captions"
        case ambient = "keep_ambient"; case beat = "cut_on_beat"
    }
}

/// One editable "recipe" step. `id` is local (SwiftUI identity), never decoded from Gemini.
struct StyleBeat: Codable, Equatable, Identifiable {
    var id = UUID()
    var t = ""           // "0–2s"
    var chip = ""        // Hook / Build / Payoff / Button
    var text = ""        // editable description
    enum CodingKeys: String, CodingKey { case t, chip, text }
    init(id: UUID = UUID(), t: String, chip: String, text: String) { self.id = id; self.t = t; self.chip = chip; self.text = text }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        t = (try? c.decode(String.self, forKey: .t)) ?? ""
        chip = (try? c.decode(String.self, forKey: .chip)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }
}

// ============================================================================
// MARK: - StyleTemplate — the unified, persisted, editable contract
// ============================================================================

/// One learned editing style. Wraps the machine `profile` (drives the M7 injection block) plus the
/// editable display surface (name / summary / habits / recipe beats). Built from a merged profile via
/// `init(from:count:)`; persisted as-is (M5).
struct StyleTemplate: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var isActive = false
    var tones: [Int] = []
    var schemaVersion = 2
    var count = 0                 // videos learned from

    var name: String              // editable
    var habits: [StyleHabit]      // editable — fully owned list (rename / remove / add)
    var beats: [StyleBeat]        // editable
    var notes: String = ""        // editable free directive — also sent to the AI (M7)
    var profile: StyleProfileRaw  // the machine profile

    /// Editable first-person summary — this IS {{style_brief}}.
    var summary: String {
        get { profile.styleBrief }
        set { profile.styleBrief = newValue }
    }
    /// Read-only display confidence (0–99).
    var confidence: Int { Self.normalizeConfidence(profile.confidence) }

    var cutLabel: String { profile.pacing.averageClipLengthSeconds > 0 ? String(format: "%.1fs", profile.pacing.averageClipLengthSeconds) : "—" }
    var lenLabel: String { profile.pacing.totalLengthSeconds > 0 ? "\(Int(profile.pacing.totalLengthSeconds.rounded()))s" : "—" }
    var hookLabel: String { let h = profile.hook.resolved; return h.isEmpty ? "—" : h }

    enum CodingKeys: String, CodingKey {
        case id; case createdAt = "created_at"; case isActive = "is_active"
        case tones; case schemaVersion = "schema_version"; case count
        case name, habits, beats, notes, profile
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id            = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        createdAt     = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        isActive      = (try? c.decode(Bool.self, forKey: .isActive)) ?? false
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 2
        count         = try c.lenientInt(.count) ?? 0
        name          = (try? c.decode(String.self, forKey: .name)).flatMap { $0.isEmpty ? nil : $0 } ?? "My style"
        // Migrate: schema 2 stores `[StyleHabit]`; schema 1 stored the fixed `StyleHabits` object.
        if let list = try? c.decode([StyleHabit].self, forKey: .habits) {
            habits = list
        } else if let legacy = try? c.decode(StyleHabits.self, forKey: .habits) {
            habits = Self.makeDefaultHabits(punch: legacy.punch, jump: legacy.jump, vo: legacy.vo,
                                            caption: legacy.caption, ambient: legacy.ambient, beat: legacy.beat)
        } else {
            habits = []
        }
        beats         = (try? c.decode([StyleBeat].self, forKey: .beats)) ?? []
        notes         = (try? c.decode(String.self, forKey: .notes)) ?? ""
        profile       = (try? c.decode(StyleProfileRaw.self, forKey: .profile)) ?? StyleProfileRaw()
        tones         = (try? c.decode([Int].self, forKey: .tones)) ?? Self.tones(for: name)
    }

    /// Build a fresh template from a (merged) profile, deriving the editable display surface.
    init(from raw: StyleProfileRaw, count: Int) {
        self.id = UUID(); self.createdAt = Date(); self.isActive = false
        self.schemaVersion = 2; self.count = count
        self.profile = raw
        // Seed a numeric B-roll heaviness from the learned categorical amount (the extraction prompt only
        // returns the category); the creator can override it in the editor. Fresh templates only.
        self.profile.broll.heaviness = Self.heaviness(forAmount: raw.broll.amount)
        self.name = Self.deriveName(raw)
        self.habits = Self.deriveHabits(raw)
        self.beats = Self.deriveBeats(raw)
        self.notes = ""
        self.tones = Self.tones(for: name)
    }

    /// Memberwise (samples / programmatic).
    init(id: UUID = UUID(), createdAt: Date = Date(), isActive: Bool = false, tones: [Int] = [],
         count: Int = 0, name: String, habits: [StyleHabit], beats: [StyleBeat], notes: String = "",
         profile: StyleProfileRaw) {
        self.id = id; self.createdAt = createdAt; self.isActive = isActive
        self.schemaVersion = 2; self.count = count
        self.name = name; self.habits = habits; self.beats = beats; self.notes = notes; self.profile = profile
        self.tones = tones.isEmpty ? Self.tones(for: name) : tones
    }

    /// Map the learned categorical b-roll amount to a starting coverage fraction (0…1).
    static func heaviness(forAmount amount: String) -> Double {
        switch amount.lowercased() {
        case "heavy":    return 0.45
        case "moderate": return 0.30
        case "minimal":  return 0.18
        default:         return 0.25
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(tones, forKey: .tones)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(count, forKey: .count)
        try c.encode(name, forKey: .name)
        try c.encode(habits, forKey: .habits)
        try c.encode(beats, forKey: .beats)
        try c.encode(notes, forKey: .notes)
        try c.encode(profile, forKey: .profile)
    }

    // MARK: derivation

    static func normalizeConfidence(_ v: Double) -> Int {
        let n = v <= 1.0 ? v * 100 : v
        return min(99, max(0, Int(n.rounded())))
    }

    static func tones(for name: String) -> [Int] {
        var h: UInt64 = 5381
        for b in name.utf8 { h = (h &* 33) &+ UInt64(b) }
        let toneCount = UInt64(FoodTone.allCases.count)
        return (0..<4).map { Int((h >> (UInt64($0) * 3)) % toneCount) }
    }

    /// A short human label, e.g. "Fast-cut close-up VO".
    static func deriveName(_ p: StyleProfileRaw) -> String {
        var parts: [String] = []
        switch p.pacing.cutStyle {
        case "fast-punchy":   parts.append("Fast-cut")
        case "slow-lingering":parts.append("Slow")
        case "medium":        parts.append("Medium")
        default: break
        }
        let hookShort: String? = {
            switch p.hook.type {
            case "food-closeup": return "close-up"
            case "bite-reaction": return "bite"
            case "talking-head-claim": return "talking"
            case "text-on-screen": return "text"
            case "plating": return "plating"
            case "action": return "action"
            case "pov": return "POV"
            default: return nil
            }
        }()
        if let hookShort { parts.append(hookShort) }
        if p.voiceover.voiceoverRatio >= 0.5 || p.voiceover.primaryMode == "mostly-voiceover-over-broll" { parts.append("VO") }
        let joined = parts.joined(separator: " ")
        guard !joined.isEmpty else { return "My style" }
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    /// The 6 canonical default toggles with their on-values. Shared by derivation and legacy migration.
    static func makeDefaultHabits(punch: Bool, jump: Bool, vo: Bool, caption: Bool, ambient: Bool, beat: Bool) -> [StyleHabit] {
        [
            StyleHabit(label: "Punch-in on the first bite", detail: "Zoom in as the fork lands", on: punch),
            StyleHabit(label: "Jump cuts over silence", detail: "Dead air trimmed, never crossfaded", on: jump),
            StyleHabit(label: "Voiceover-led story", detail: "You narrate; music sits low", on: vo),
            StyleHabit(label: "Burned-in captions", detail: "Serif italic, your phrasing", on: caption),
            StyleHabit(label: "Keep the sizzle audio", detail: "Pan & sizzle under the voice", on: ambient),
            StyleHabit(label: "Cut on the beat", detail: "Hard cuts on the downbeat", on: beat),
        ]
    }

    static func deriveHabits(_ p: StyleProfileRaw) -> [StyleHabit] {
        let moveText = p.signatureMoves.map { $0.move.lowercased() }.joined(separator: " ")
        return makeDefaultHabits(
            punch: moveText.contains("punch") || moveText.contains("push-in") || moveText.contains("zoom"),
            jump: p.pacing.cutStyle == "fast-punchy" || (p.pacing.cutStyleCustom?.lowercased().contains("jump") ?? false),
            vo: p.voiceover.voiceoverRatio >= 0.4 || p.voiceover.primaryMode == "mostly-voiceover-over-broll",
            caption: p.textAndGraphics.usesTextOverlays,
            ambient: p.audio.keepsNaturalFoodSounds,
            beat: p.audio.bed == "trending-sound" || (p.pacing.cutStyle == "fast-punchy" && p.audio.bed == "background-music")
        )
    }

    static func deriveBeats(_ p: StyleProfileRaw) -> [StyleBeat] {
        let arc = p.structure.arc.isEmpty ? ["hook", "build", "payoff", "button"] : p.structure.arc
        let total = max(8, p.pacing.totalLengthSeconds > 0 ? p.pacing.totalLengthSeconds : 30)
        let n = arc.count
        var beats: [StyleBeat] = []
        var t0 = 0.0
        for (i, label) in arc.enumerated() {
            let t1 = (i == n - 1) ? total : t0 + total / Double(n)
            let chip = label.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
            let text: String
            if i == 0, !p.hook.description.isEmpty { text = p.hook.description }
            else if i == n - 1, !p.closing.description.isEmpty { text = p.closing.description }
            else { text = chip }
            beats.append(StyleBeat(t: "\(Int(t0.rounded()))–\(Int(t1.rounded()))s", chip: chip, text: text))
            t0 = t1
        }
        return beats
    }

    var debugSummary: String {
        """
        StyleTemplate · "\(name)" · \(confidence)% · \(count) videos
          summary: \(summary)
          hook:    \(profile.hook.resolved) (~\(Int(profile.hook.opensWithinSeconds))s)
          pacing:  \(cutLabel) avg · \(lenLabel) total · \(profile.pacing.cutStyleResolved)
          vo:      \(String(format: "%.2f", profile.voiceover.voiceoverRatio)) · broll: \(profile.broll.amount)/\(profile.broll.usageResolved)
          arc:     \(profile.structure.arcText)
          habits:  \(habits.map { "\($0.label)=\($0.on ? "on" : "off")" }.joined(separator: ", "))
          notes:   \(notes.isEmpty ? "—" : notes)
          beats:   \(beats.map { "\($0.t) \($0.chip)" }.joined(separator: " · "))
        """
    }

    // MARK: sample + self-test

    static let sample: StyleTemplate = {
        var raw = StyleProfileRaw()
        raw.styleBrief = "I open on a question, push in on the first bite, and let my voice carry it — fast cuts, captions in my own words, music kept low."
        raw.hook = HookInfo(); raw.hook.type = "talking-head-claim"; raw.hook.opensWithinSeconds = 2; raw.hook.hasTextOverlay = true
        raw.hook.description = "A spoken question over a tight push-in on the dish."
        raw.pacing = PacingInfo(); raw.pacing.totalLengthSeconds = 28; raw.pacing.averageClipLengthSeconds = 1.4; raw.pacing.cutStyle = "fast-punchy"
        raw.voiceover = VoiceoverInfo(); raw.voiceover.primaryMode = "mostly-voiceover-over-broll"; raw.voiceover.voiceoverRatio = 0.7; raw.voiceover.talksToCamera = true
        raw.broll = BrollInfo(); raw.broll.amount = "moderate"; raw.broll.usage = "continuous-under-narration"; raw.broll.favoredShots = ["food-closeup", "plating", "bite-reaction"]
        raw.structure = StructureInfo(arc: ["hook", "build", "payoff", "button"])
        raw.textAndGraphics = TextGraphicsInfo(); raw.textAndGraphics.usesTextOverlays = true; raw.textAndGraphics.textStyle = "captions"; raw.textAndGraphics.amount = "moderate"
        raw.audio = AudioInfo(); raw.audio.bed = "background-music"; raw.audio.keepsNaturalFoodSounds = true
        raw.closing = ClosingInfo(type: "call-to-action", description: "A caption line and a soft CTA to follow.")
        raw.signatureMoves = [SignatureMove(move: "punch-in on the first bite", likelyHabit: 0.9)]
        raw.sceneTypesPresent = ["food-closeup", "talking-head", "bite-reaction", "plating"]
        raw.confidence = 0.88
        return StyleTemplate(from: raw, count: 24)
    }()

    #if DEBUG
    static func runSelfTest() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? e.encode(sample),
              let back = try? d.decode(StyleTemplate.self, from: data),
              back.name == sample.name, back.profile.hook == sample.profile.hook,
              back.habits.map(\.label) == sample.habits.map(\.label), back.beats.count == sample.beats.count,
              back.summary == sample.summary else {
            Log.app("⚠️ StyleTemplate self-test MISMATCH."); return
        }
        Log.app("🍳 StyleTemplate self-test round-trip OK.")
    }
    #endif
}
