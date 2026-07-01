import Foundation

/// The **DECIDE** output — a THIN decisions object that references PERCEIVE shot ids (never re-describes
/// shots). Mirrors `tools/promptlab/decide-schema.json`. `EditPlanAdapter` merges this with the
/// `ContentIndex` into a full `EditPlan`. Lenient-decoded like the rest.
struct EditDecisions: Decodable, Equatable {
    let recommendedDuration: Double
    let recommendedHook: String
    let hookId: Int
    let coldOpen: [Int]
    let finalEditOrder: [Int]
    let trims: [Trim]
    let voiceovers: [Voiceover]
    let brollPlacements: [BrollDecision]
    let editNotes: [EditNote]
    let styleMatchNotes: String
    let videoSummary: String

    struct Trim: Decodable, Equatable {
        let shotId: Int; let trimToSeconds: Double; let reason: String
        enum CodingKeys: String, CodingKey { case shotId = "shot_id"; case trimToSeconds = "trim_to_seconds"; case reason }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            shotId = try c.lenientInt(.shotId) ?? -1
            trimToSeconds = try c.lenientDouble(.trimToSeconds) ?? 0
            reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        }
        init(shotId: Int, trimToSeconds: Double, reason: String) { self.shotId = shotId; self.trimToSeconds = trimToSeconds; self.reason = reason }
    }
    struct Voiceover: Decodable, Equatable {
        let shotId: Int; let reason: String
        enum CodingKeys: String, CodingKey { case shotId = "shot_id"; case reason }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            shotId = try c.lenientInt(.shotId) ?? -1
            reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        }
        init(shotId: Int, reason: String) { self.shotId = shotId; self.reason = reason }
    }
    struct BrollDecision: Decodable, Equatable {
        let overShotId: Int; let brollShotId: Int; let startOffsetSeconds: Double; let durationSeconds: Double; let reason: String
        enum CodingKeys: String, CodingKey {
            case overShotId = "over_shot_id"; case brollShotId = "broll_shot_id"
            case startOffsetSeconds = "start_offset_seconds"; case durationSeconds = "duration_seconds"; case reason
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            overShotId = try c.lenientInt(.overShotId) ?? -1
            brollShotId = try c.lenientInt(.brollShotId) ?? -1
            startOffsetSeconds = max(0, try c.lenientDouble(.startOffsetSeconds) ?? 0)
            durationSeconds = try c.lenientDouble(.durationSeconds) ?? 0
            reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        }
        init(overShotId: Int, brollShotId: Int, startOffsetSeconds: Double, durationSeconds: Double, reason: String) {
            self.overShotId = overShotId; self.brollShotId = brollShotId; self.startOffsetSeconds = startOffsetSeconds
            self.durationSeconds = durationSeconds; self.reason = reason
        }
    }
    struct EditNote: Decodable, Equatable {
        let shotId: Int; let note: String
        enum CodingKeys: String, CodingKey { case shotId = "shot_id"; case note }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            shotId = try c.lenientInt(.shotId) ?? -1
            note = (try? c.decode(String.self, forKey: .note)) ?? ""
        }
        init(shotId: Int, note: String) { self.shotId = shotId; self.note = note }
    }

    enum CodingKeys: String, CodingKey {
        case recommendedDuration = "recommended_duration"
        case recommendedHook = "recommended_hook"
        case hookId = "hook_id"
        case coldOpen = "cold_open"
        case finalEditOrder = "final_edit_order"
        case trims
        case voiceovers
        case brollPlacements = "broll_placements"
        case editNotes = "edit_notes"
        case styleMatchNotes = "style_match_notes"
        case videoSummary = "video_summary"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recommendedDuration = try c.lenientDouble(.recommendedDuration) ?? 0
        recommendedHook = (try? c.decode(String.self, forKey: .recommendedHook)) ?? ""
        hookId = try c.lenientInt(.hookId) ?? -1
        coldOpen = (try? c.decode([Int].self, forKey: .coldOpen)) ?? []
        finalEditOrder = (try? c.decode([Int].self, forKey: .finalEditOrder)) ?? []
        trims = (try? c.decode([Trim].self, forKey: .trims)) ?? []
        voiceovers = (try? c.decode([Voiceover].self, forKey: .voiceovers)) ?? []
        brollPlacements = (try? c.decode([BrollDecision].self, forKey: .brollPlacements)) ?? []
        editNotes = (try? c.decode([EditNote].self, forKey: .editNotes)) ?? []
        styleMatchNotes = (try? c.decode(String.self, forKey: .styleMatchNotes)) ?? ""
        videoSummary = (try? c.decode(String.self, forKey: .videoSummary)) ?? ""
    }

    init(recommendedDuration: Double, recommendedHook: String, hookId: Int, coldOpen: [Int], finalEditOrder: [Int],
         trims: [Trim], voiceovers: [Voiceover], brollPlacements: [BrollDecision], editNotes: [EditNote],
         styleMatchNotes: String, videoSummary: String) {
        self.recommendedDuration = recommendedDuration; self.recommendedHook = recommendedHook; self.hookId = hookId
        self.coldOpen = coldOpen; self.finalEditOrder = finalEditOrder; self.trims = trims; self.voiceovers = voiceovers
        self.brollPlacements = brollPlacements; self.editNotes = editNotes; self.styleMatchNotes = styleMatchNotes
        self.videoSummary = videoSummary
    }

    static func parse(fromRawModelText raw: String) throws -> EditDecisions {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
            if let close = s.range(of: "```", options: .backwards) { s = String(s[..<close.lowerBound]) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end,
              let data = String(s[start...end]).data(using: .utf8) else { throw EditPlanParseError.noJSONObject }
        do { return try JSONDecoder().decode(EditDecisions.self, from: data) }
        catch { throw EditPlanParseError.decodeFailed(error.localizedDescription) }
    }
}
