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

/// A montage-style hook — several very short clips back-to-back before the creator's own material, often
/// borrowed clips of OTHER creators reviewing the same place (social proof). **Capture-only**: reproduction
/// is deferred, so this feeds the template display + a cut-time Polish nudge, never the cut prompt.
struct MontageInfo: Codable, Equatable {
    var isMontage = false
    var source = ""                  // "other-creators" | "own-footage"
    var clipCountEstimate = 0
    var avgClipSeconds: Double = 0
    enum CodingKeys: String, CodingKey {
        case isMontage = "is_montage"; case source
        case clipCountEstimate = "clip_count_estimate"; case avgClipSeconds = "avg_clip_seconds"
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        isMontage = (try? c.decode(Bool.self, forKey: .isMontage)) ?? false
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        clipCountEstimate = try c.lenientInt(.clipCountEstimate) ?? 0
        avgClipSeconds = try c.lenientDouble(.avgClipSeconds) ?? 0
    }
}

struct HookInfo: Codable, Equatable {
    var type = ""; var typeCustom: String? = nil
    var opensWithinSeconds: Double = 0
    var hasTextOverlay = false
    var description = ""
    var montage = MontageInfo()
    enum CodingKeys: String, CodingKey {
        case type; case typeCustom = "type_custom"
        case opensWithinSeconds = "opens_within_seconds"
        case hasTextOverlay = "has_text_overlay"; case description; case montage
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        typeCustom = try? c.decodeIfPresent(String.self, forKey: .typeCustom)
        opensWithinSeconds = try c.lenientDouble(.opensWithinSeconds) ?? 0
        hasTextOverlay = (try? c.decode(Bool.self, forKey: .hasTextOverlay)) ?? false
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        montage = (try? c.decode(MontageInfo.self, forKey: .montage)) ?? MontageInfo()
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
    var example = ""                 // the video-specific instance ("e.g. chicken skin") — labels stay format-level
    var evidenceCount = 1            // sources containing this beat (1 for a single-video learn)
    var confirmation: String? = nil  // user-owned (Reveal/editor); presentation only, `core` drives the cut
    enum CodingKeys: String, CodingKey {
        case label; case timeHint = "time_hint"; case core
        case example; case evidenceCount = "evidence_count"; case confirmation
    }
    init(id: UUID = UUID(), label: String = "", timeHint: String = "", core: Bool = false,
         example: String = "", evidenceCount: Int = 1, confirmation: String? = nil) {
        self.id = id; self.label = label; self.timeHint = timeHint; self.core = core
        self.example = example; self.evidenceCount = evidenceCount; self.confirmation = confirmation
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        timeHint = (try? c.decode(String.self, forKey: .timeHint)) ?? ""
        core = (try? c.decode(Bool.self, forKey: .core)) ?? false
        example = (try? c.decode(String.self, forKey: .example)) ?? ""
        evidenceCount = try c.lenientInt(.evidenceCount) ?? 1
        confirmation = try? c.decodeIfPresent(String.self, forKey: .confirmation)
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

// ============================================================================
// MARK: - Verbal identity + learned habits (schema 3)
// ============================================================================

/// The four learned-habit kinds. Only `selection`/`verbal` are ever sent to the cut prompt (non-executable
/// habits are prompt noise — Decision #10); `supplied-footage`/`visual-effect` render as "coming soon" rows.
/// Stored as plain strings (defensive decode), canonicalized via `normalize`.
enum HabitKind {
    static let selection = "selection"
    static let verbal = "verbal"
    static let suppliedFootage = "supplied-footage"
    static let visualEffect = "visual-effect"

    /// Canonicalize model spellings ("visual_effect", "Supplied Footage"); unknown/missing → `selection` —
    /// the correct-direction default: a silently-lost real habit is worse than a tolerably noisy one.
    static func normalize(_ raw: String?) -> String {
        let k = (raw ?? "").lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch k {
        case verbal:          return verbal
        case suppliedFootage: return suppliedFootage
        case visualEffect:    return visualEffect
        default:              return selection
        }
    }
    /// Whether the cut prompt may carry this habit.
    static func isAppliable(_ kind: String) -> Bool { kind == selection || kind == verbal }
}

/// One line this creator repeats — spoken ("let's see if it's worth the hype") or on-screen text
/// ("CRAVING SCORE: __"). `pattern` holds the templated form when a slot varies ("Day {n} of …") and is the
/// dedupe/evidence key; `quote` stays the verbatim example. `confirmation` is user-owned, written by the
/// Reveal: nil (unasked) | "every" | "sometimes" — "leave it out" removes the row + suppresses its key.
/// `id` is local SwiftUI identity, never decoded.
struct RecurringLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var quote = ""
    var role = ""                    // hook | verdict | sign-off | transition | throughout
    var medium = "spoken"            // spoken | text-overlay
    var pattern: String? = nil
    var position = ""                // opening | mid | closing — as observed in the finished video
    var deliveryNote = ""
    var likelyHabit: Double = 0
    var evidenceCount = 1            // sources containing this line (1 for a single-video learn)
    var confirmation: String? = nil
    enum CodingKeys: String, CodingKey {
        case quote; case role = "where_used"; case medium; case pattern; case position
        case deliveryNote = "delivery_note"; case likelyHabit = "likely_habit"
        case evidenceCount = "evidence_count"; case confirmation
    }
    init(id: UUID = UUID(), quote: String = "", role: String = "", medium: String = "spoken",
         pattern: String? = nil, position: String = "", deliveryNote: String = "",
         likelyHabit: Double = 0, evidenceCount: Int = 1, confirmation: String? = nil) {
        self.id = id; self.quote = quote; self.role = role; self.medium = medium
        self.pattern = pattern; self.position = position; self.deliveryNote = deliveryNote
        self.likelyHabit = likelyHabit; self.evidenceCount = evidenceCount; self.confirmation = confirmation
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        quote = (try? c.decode(String.self, forKey: .quote)) ?? ""
        role = (try? c.decode(String.self, forKey: .role)) ?? ""
        medium = ((try? c.decode(String.self, forKey: .medium)) ?? "spoken").lowercased() == "text-overlay" ? "text-overlay" : "spoken"
        pattern = try? c.decodeIfPresent(String.self, forKey: .pattern)
        position = (try? c.decode(String.self, forKey: .position)) ?? ""
        deliveryNote = (try? c.decode(String.self, forKey: .deliveryNote)) ?? ""
        likelyHabit = try c.lenientDouble(.likelyHabit) ?? 0
        evidenceCount = try c.lenientInt(.evidenceCount) ?? 1
        confirmation = try? c.decodeIfPresent(String.self, forKey: .confirmation)
    }
    /// Normalized dedupe/evidence/suppression key — the pattern when present, else the quote.
    var key: String {
        let base = (pattern?.isEmpty == false) ? pattern! : quote
        return base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    var isSpoken: Bool { medium != "text-overlay" }
}

/// This creator's verbal identity — tone, POV, rating formula, sign-off, recurring lines.
struct VerbalStyleInfo: Codable, Equatable {
    var tone = ""
    var pov = ""
    var ratingFormat = ""
    var ratingScope = ""             // overall | per-item | both
    var signoff = ""
    var ratingConfirmation: String? = nil     // Reveal write-backs for the two scalar signatures
    var signoffConfirmation: String? = nil
    var recurringLines: [RecurringLine] = []
    enum CodingKeys: String, CodingKey {
        case tone, pov
        case ratingFormat = "rating_format"; case ratingScope = "rating_scope"; case signoff
        case ratingConfirmation = "rating_confirmation"; case signoffConfirmation = "signoff_confirmation"
        case recurringLines = "recurring_lines"
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        tone = (try? c.decode(String.self, forKey: .tone)) ?? ""
        pov = (try? c.decode(String.self, forKey: .pov)) ?? ""
        ratingFormat = (try? c.decode(String.self, forKey: .ratingFormat)) ?? ""
        ratingScope = (try? c.decode(String.self, forKey: .ratingScope)) ?? ""
        signoff = (try? c.decode(String.self, forKey: .signoff)) ?? ""
        ratingConfirmation = try? c.decodeIfPresent(String.self, forKey: .ratingConfirmation)
        signoffConfirmation = try? c.decodeIfPresent(String.self, forKey: .signoffConfirmation)
        recurringLines = (try? c.decode([RecurringLine].self, forKey: .recurringLines)) ?? []
    }
    var isEmpty: Bool {
        tone.isEmpty && pov.isEmpty && ratingFormat.isEmpty && signoff.isEmpty && recurringLines.isEmpty
    }
}

/// A model-authored habit in the creator's own terms — becomes a `StyleHabit` row on the template.
struct HabitCandidate: Codable, Equatable {
    var label = ""
    var detail = ""
    var likelyHabit: Double = 0
    var timesSeenInVideo = 1         // within-video repetition — real single-video evidence
    var evidenceCount = 1
    var kind = HabitKind.selection
    enum CodingKeys: String, CodingKey {
        case label, detail, kind
        case likelyHabit = "likely_habit"; case timesSeenInVideo = "times_seen_in_video"
        case evidenceCount = "evidence_count"
    }
    init(label: String = "", detail: String = "", likelyHabit: Double = 0,
         timesSeenInVideo: Int = 1, evidenceCount: Int = 1, kind: String = HabitKind.selection) {
        self.label = label; self.detail = detail; self.likelyHabit = likelyHabit
        self.timesSeenInVideo = timesSeenInVideo; self.evidenceCount = evidenceCount
        self.kind = HabitKind.normalize(kind)
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
        likelyHabit = try c.lenientDouble(.likelyHabit) ?? 0
        timesSeenInVideo = try c.lenientInt(.timesSeenInVideo) ?? 1
        evidenceCount = try c.lenientInt(.evidenceCount) ?? 1
        kind = HabitKind.normalize(try? c.decode(String.self, forKey: .kind))
    }
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
    // Schema 3 — verbal identity + model-authored habits + the Reveal's narration. All default-empty so
    // v2 persisted profiles and old-prompt responses still parse.
    var verbalStyle = VerbalStyleInfo()
    var habitCandidates: [HabitCandidate] = []
    var revealScript: [String] = []

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
        case verbalStyle = "verbal_style"
        case habitCandidates = "habit_candidates"
        case revealScript = "reveal_script"
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
        verbalStyle     = (try? c.decode(VerbalStyleInfo.self, forKey: .verbalStyle)) ?? VerbalStyleInfo()
        habitCandidates = (try? c.decode([HabitCandidate].self, forKey: .habitCandidates)) ?? []
        revealScript    = ((try? c.decode([String].self, forKey: .revealScript)) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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

        // Verbal identity + habit candidates (FALLBACK path — the consolidation model handles N≥2 normally
        // and dedupes by MEANING; this exact-key merge only runs when that call fails). Union recurring
        // lines by normalized pattern/quote key; evidence = number of profiles containing the key. Scalars
        // (tone/pov/rating/signoff) stay from the most-confident profile already in `merged`.
        var lineOrder: [String] = []
        var lineByKey: [String: RecurringLine] = [:]
        var lineCounts: [String: Int] = [:]
        for p in profiles {
            var seenHere = Set<String>()
            for l in p.verbalStyle.recurringLines {
                let k = l.key
                guard !k.isEmpty, seenHere.insert(k).inserted else { continue }
                if lineByKey[k] == nil { lineOrder.append(k); lineByKey[k] = l }
                lineCounts[k, default: 0] += 1
            }
        }
        merged.verbalStyle.recurringLines = lineOrder
            .compactMap { k -> RecurringLine? in
                guard var l = lineByKey[k] else { return nil }
                l.evidenceCount = lineCounts[k] ?? 1
                return l
            }
            .sorted { a, b in a.evidenceCount != b.evidenceCount ? a.evidenceCount > b.evidenceCount : a.likelyHabit > b.likelyHabit }
            .prefix(6).map { $0 }

        var habOrder: [String] = []
        var habByKey: [String: HabitCandidate] = [:]
        var habCounts: [String: Int] = [:]
        for p in profiles {
            var seenHere = Set<String>()
            for h in p.habitCandidates {
                let k = h.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !k.isEmpty, seenHere.insert(k).inserted else { continue }
                if var e = habByKey[k] {
                    e.timesSeenInVideo = max(e.timesSeenInVideo, h.timesSeenInVideo)
                    e.likelyHabit = max(e.likelyHabit, h.likelyHabit)
                    habByKey[k] = e
                } else { habOrder.append(k); habByKey[k] = h }
                habCounts[k, default: 0] += 1
            }
        }
        merged.habitCandidates = habOrder.compactMap { k -> HabitCandidate? in
            guard var h = habByKey[k] else { return nil }
            h.evidenceCount = habCounts[k] ?? 1
            return h
        }
        // revealScript: keep the most-confident profile's (already in `merged`) — the consolidation model
        // is the one that rewrites it as a cross-video consistency story.

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
            var example: [String: String] = [:]
            for sec in perProfile {
                var seenHere = Set<String>()               // count each label at most once per example
                for b in sec.beats {
                    let key = b.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !key.isEmpty, seenHere.insert(key).inserted else { continue }
                    if counts[key] == nil { order.append(key); display[key] = b.label; timeHint[key] = b.timeHint }
                    if example[key] == nil || example[key]!.isEmpty { example[key] = b.example }
                    counts[key, default: 0] += 1
                }
            }
            let beats = order.enumerated()
                .sorted { a, b in
                    let ca = counts[a.element] ?? 0, cb = counts[b.element] ?? 0
                    return ca != cb ? ca > cb : a.offset < b.offset
                }
                .map { (_, key) in
                    SectionBeat(label: display[key] ?? key, timeHint: timeHint[key] ?? "",
                                core: (counts[key] ?? 0) == n,
                                example: example[key] ?? "", evidenceCount: counts[key] ?? 1)
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
    var evidenceCount = 1                    // display only — sources this habit appeared in
    var kind = HabitKind.selection           // selection/verbal = live toggle; else "coming soon" row
    enum CodingKeys: String, CodingKey {     // `id` excluded → synthesized fresh
        case label, detail, on, kind
        case evidenceCount = "evidence_count"
    }
    init(id: UUID = UUID(), label: String, detail: String? = nil, on: Bool = true,
         evidenceCount: Int = 1, kind: String = HabitKind.selection) {
        self.id = id; self.label = label; self.detail = detail; self.on = on
        self.evidenceCount = evidenceCount; self.kind = HabitKind.normalize(kind)
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        on = (try? c.decode(Bool.self, forKey: .on)) ?? true
        evidenceCount = try c.lenientInt(.evidenceCount) ?? 1
        kind = HabitKind.normalize(try? c.decode(String.self, forKey: .kind))
    }
    /// Whether this habit may be sent to the cut prompt (vs a "coming soon" display row).
    var isAppliable: Bool { HabitKind.isAppliable(kind) }
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
// MARK: - EvidenceTier — one shared story for every badge surface
// ============================================================================

/// Presentation tier for evidence badges — shared by the editor beats, habits, and the signature card so
/// every surface tells the same story. Gold "EVERY VIDEO" is EARNED (user-confirmed only); automatic
/// all-sources evidence reads factually ("ALL 3 VIDEOS" — a 2-video sample never claims a career). At
/// N=1 unconfirmed rows show NO badge — a page of identical "SEEN ONCE" hedges is negative texture; the
/// section header carries the one-video honesty line instead. Badges are presentation ONLY: `core` stays
/// the constraint-builder input.
enum EvidenceTier: Equatable {
    case confirmedEvery      // user answered "Every video"
    case allSources(Int)     // seen in all N sources (N≥2), unconfirmed
    case partial(Int, Int)   // seen in k of N (N≥2)
    case sometimes           // user answered "Sometimes"
    case none                // N=1 unconfirmed → no per-row badge

    static func tier(confirmation: String?, evidence: Int, sourceCount: Int) -> EvidenceTier {
        if confirmation == "every" { return .confirmedEvery }
        if confirmation == "sometimes" { return .sometimes }
        guard sourceCount >= 2 else { return .none }
        if evidence >= sourceCount { return .allSources(sourceCount) }
        return .partial(max(1, evidence), sourceCount)
    }

    var label: String? {
        switch self {
        case .confirmedEvery:        return "EVERY VIDEO"
        case .allSources(let n):     return "ALL \(n) VIDEOS"
        case .partial(let k, let n): return "\(k) OF \(n)"
        case .sometimes:             return "SOMETIMES"
        case .none:                  return nil
        }
    }
    /// Gold badges celebrate; soft badges inform.
    var isGold: Bool {
        switch self { case .confirmedEvery, .allSources: return true; default: return false }
    }
}

// ============================================================================
// MARK: - StyleTemplate — the unified, persisted, editable contract
// ============================================================================

/// One learned editing style. Wraps the machine `profile` (drives the M7 injection block) plus the
/// editable display surface (name / summary / habits / recipe beats). Built from a merged profile via
/// `init(from:count:)`; persisted as-is (M5).
struct StyleTemplate: Codable, Equatable, Identifiable {
    /// Bump when the persisted shape changes; `FileTemplateStore.list()` skips anything newer.
    static let currentSchemaVersion = 3

    var id = UUID()
    var createdAt = Date()
    var isActive = false
    var tones: [Int] = []
    var schemaVersion = StyleTemplate.currentSchemaVersion
    var count = 0                 // videos learned from

    var name: String              // editable
    var habits: [StyleHabit]      // editable — fully owned list (rename / remove / add)
    var beats: [StyleBeat]        // editable
    var notes: String = ""        // editable free directive — also sent to the AI (M7)
    var profile: StyleProfileRaw  // the machine profile
    /// Machine-owned: the per-video profiles this template was built from (schema 3) — refinement
    /// re-consolidates over these + any new videos. Empty for legacy v2 templates (treated as
    /// `[profile]` pseudo-source at refine time).
    var sources: [StyleProfileRaw] = []
    /// The last model-authored style brief — lets refinement tell "user edited the summary" (keep it)
    /// from "still machine text" (safe to replace).
    var machineSummary: String? = nil
    /// Normalized keys (RecurringLine.key / habit labels) the user rejected ("leave it out" / editor ✕).
    /// Consulted before any machine append; also sent to consolidation as REJECTED LINES.
    var suppressed: [String] = []

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
        case sources; case machineSummary = "machine_summary"; case suppressed
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
        sources       = (try? c.decode([StyleProfileRaw].self, forKey: .sources)) ?? []
        machineSummary = try? c.decodeIfPresent(String.self, forKey: .machineSummary)
        suppressed    = (try? c.decode([String].self, forKey: .suppressed)) ?? []
    }

    /// Build a fresh template from a (merged) profile, deriving the editable display surface.
    /// `sources` = the per-video profiles the merge came from (persisted so refinement can re-consolidate).
    init(from raw: StyleProfileRaw, count: Int, sources: [StyleProfileRaw] = []) {
        self.id = UUID(); self.createdAt = Date(); self.isActive = false
        self.schemaVersion = Self.currentSchemaVersion; self.count = count
        self.profile = raw
        self.sources = sources
        self.machineSummary = raw.styleBrief
        self.suppressed = []
        // Seed a numeric B-roll heaviness from the learned categorical amount (the extraction prompt only
        // returns the category); the creator can override it in the editor. Fresh templates only.
        self.profile.broll.heaviness = Self.heaviness(forAmount: raw.broll.amount)
        self.name = Self.deriveName(raw)
        // Model-authored habits (already ordered most-distinctive-first by the prompt): appliable kinds
        // start ON — the Reveal/editor is the correction surface for N=1 uncertainty; coming-soon kinds
        // start off (they're display rows, never sent to the cut prompt). Legacy fallback: the fixed 6.
        if raw.habitCandidates.isEmpty {
            self.habits = Self.deriveHabits(raw)
        } else {
            self.habits = raw.habitCandidates.prefix(6).map { cand in
                StyleHabit(label: cand.label, detail: cand.detail.isEmpty ? nil : cand.detail,
                           on: HabitKind.isAppliable(cand.kind),
                           evidenceCount: cand.evidenceCount, kind: cand.kind)
            }
        }
        self.beats = Self.deriveBeats(raw)
        self.notes = ""
        self.tones = Self.tones(for: name)
    }

    /// Memberwise (samples / programmatic).
    init(id: UUID = UUID(), createdAt: Date = Date(), isActive: Bool = false, tones: [Int] = [],
         count: Int = 0, name: String, habits: [StyleHabit], beats: [StyleBeat], notes: String = "",
         profile: StyleProfileRaw, sources: [StyleProfileRaw] = [], machineSummary: String? = nil,
         suppressed: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.isActive = isActive
        self.schemaVersion = Self.currentSchemaVersion; self.count = count
        self.name = name; self.habits = habits; self.beats = beats; self.notes = notes; self.profile = profile
        self.sources = sources; self.machineSummary = machineSummary; self.suppressed = suppressed
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
        try c.encode(sources, forKey: .sources)
        try c.encodeIfPresent(machineSummary, forKey: .machineSummary)
        try c.encode(suppressed, forKey: .suppressed)
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
        StyleTemplate · "\(name)" · \(confidence)% · \(count) videos · schema \(schemaVersion) · \(sources.count) sources
          summary: \(summary)
          hook:    \(profile.hook.resolved) (~\(Int(profile.hook.opensWithinSeconds))s)\(profile.hook.montage.isMontage ? " · MONTAGE (\(profile.hook.montage.source))" : "")
          pacing:  \(cutLabel) avg · \(lenLabel) total · \(profile.pacing.cutStyleResolved)
          vo:      \(String(format: "%.2f", profile.voiceover.voiceoverRatio)) · broll: \(profile.broll.amount)/\(profile.broll.usageResolved)
          arc:     \(profile.structure.arcText)
          voice:   \(profile.verbalStyle.tone.isEmpty ? "—" : profile.verbalStyle.tone) · \(profile.verbalStyle.pov.isEmpty ? "—" : profile.verbalStyle.pov)
          signoff: \(profile.verbalStyle.signoff.isEmpty ? "—" : "“\(profile.verbalStyle.signoff)”") · rating: \(profile.verbalStyle.ratingFormat.isEmpty ? "—" : profile.verbalStyle.ratingFormat)
          lines:   \(profile.verbalStyle.recurringLines.isEmpty ? "—" : profile.verbalStyle.recurringLines.map { "“\($0.quote)” [\($0.role)/\($0.medium) ×\($0.evidenceCount)]" }.joined(separator: " · "))
          habits:  \(habits.map { "\($0.label)=\($0.isAppliable ? ($0.on ? "on" : "off") : "soon")" }.joined(separator: ", "))
          reveal:  \(profile.revealScript.count) lines · suppressed: \(suppressed.count)
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
        raw.verbalStyle.tone = "hyped, playful"
        raw.verbalStyle.pov = "solo-first-person"
        raw.verbalStyle.ratingFormat = "a rating out of 10, sometimes with a decimal"
        raw.verbalStyle.ratingScope = "overall"
        raw.verbalStyle.signoff = "we'll see you in the next one"
        raw.verbalStyle.recurringLines = [
            RecurringLine(quote: "let's see if it's worth the hype", role: "hook", position: "opening",
                          deliveryNote: "spoken straight to camera", likelyHabit: 0.9),
            RecurringLine(quote: "CRAVING SCORE: 8.7", role: "verdict", medium: "text-overlay",
                          pattern: "CRAVING SCORE: {score}", position: "closing", likelyHabit: 0.8)
        ]
        raw.habitCandidates = [
            HabitCandidate(label: "Open on a spoken question", detail: "The hook is always a to-camera question",
                           likelyHabit: 0.9, timesSeenInVideo: 1, kind: HabitKind.verbal),
            HabitCandidate(label: "Punch-in on the first bite", detail: "Zoom as the fork lands",
                           likelyHabit: 0.85, timesSeenInVideo: 2, kind: HabitKind.visualEffect)
        ]
        raw.revealScript = ["You open on a question and let your voice carry the story.",
                            "\"let's see if it's worth the hype\" — that's how you pull people in."]
        return StyleTemplate(from: raw, count: 24, sources: [raw])
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
        // Schema-3 leaf fields (ids are synthesized fresh on decode, so compare values, never whole structs
        // with `==` — same reason the base test maps labels).
        let vs = sample.profile.verbalStyle, vb = back.profile.verbalStyle
        guard back.schemaVersion == currentSchemaVersion,
              back.sources.count == sample.sources.count,
              back.machineSummary == sample.machineSummary,
              back.suppressed == sample.suppressed,
              vb.tone == vs.tone, vb.pov == vs.pov, vb.ratingFormat == vs.ratingFormat,
              vb.ratingScope == vs.ratingScope, vb.signoff == vs.signoff,
              vb.recurringLines.map(\.quote) == vs.recurringLines.map(\.quote),
              vb.recurringLines.map(\.medium) == vs.recurringLines.map(\.medium),
              vb.recurringLines.map(\.pattern) == vs.recurringLines.map(\.pattern),
              vb.recurringLines.map(\.position) == vs.recurringLines.map(\.position),
              vb.recurringLines.map(\.evidenceCount) == vs.recurringLines.map(\.evidenceCount),
              back.profile.habitCandidates == sample.profile.habitCandidates,
              back.profile.revealScript == sample.profile.revealScript,
              back.profile.hook.montage == sample.profile.hook.montage,
              back.habits.map(\.kind) == sample.habits.map(\.kind),
              back.habits.map(\.evidenceCount) == sample.habits.map(\.evidenceCount),
              back.beats.count == sample.beats.count else {
            Log.app("⚠️ StyleTemplate self-test MISMATCH (schema-3 fields)."); return
        }
        Log.app("🍳 StyleTemplate self-test round-trip OK (schema \(currentSchemaVersion)).")
    }
    #endif
}
