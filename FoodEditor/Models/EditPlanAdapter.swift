import Foundation

/// **ADAPT** — merge a DECIDE `EditDecisions` with the PERCEIVE `ContentIndex` into a full `EditPlan` the
/// rest of the app renders UNCHANGED. Pure + deterministic; this is the "code = assembler/safety-net" step.
/// The `Shot`s ARE the `Segment`s (same id/timestamps/scene_type/section/topic), so this COPIES the index
/// fields verbatim and only DERIVES the editorial ones — making coverage/timing/scene violations impossible.
/// `keep` is implicit: a shot is kept iff it's in `final_edit_order` or used as a b-roll source. Mirrors
/// `tools/promptlab/adapt-plan.mjs` (the lab is the source of truth). Asserts → warns; never rewrites.
enum EditPlanAdapter {
    static func adapt(index: ContentIndex, decisions: EditDecisions) -> (plan: EditPlan, warnings: [String]) {
        var warnings: [String] = []
        let byId = Dictionary(index.shots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let order = decisions.finalEditOrder
        let broll = decisions.brollPlacements

        let trimById = Dictionary(decisions.trims.map { ($0.shotId, $0) }, uniquingKeysWith: { a, _ in a })
        let voById   = Dictionary(decisions.voiceovers.map { ($0.shotId, $0) }, uniquingKeysWith: { a, _ in a })
        let noteById = Dictionary(decisions.editNotes.map { ($0.shotId, $0) }, uniquingKeysWith: { a, _ in a })

        // kept = in the order OR used as a b-roll source.
        var kept = Set(order)
        for p in broll { kept.insert(p.brollShotId) }

        // ---- asserts (warn only; on-device EditPlanRepair still repairs at runtime) ----
        if decisions.hookId != order.first { warnings.append("hook_id \(decisions.hookId) != final_edit_order[0] \(order.first.map(String.init) ?? "—")") }
        if !decisions.coldOpen.enumerated().allSatisfy({ idx, id in idx < order.count && order[idx] == id }) {
            warnings.append("cold_open \(decisions.coldOpen) is not a prefix of final_edit_order")
        }
        var seen = Set<Int>()
        for id in order {
            if byId[id] == nil { warnings.append("final_edit_order references unknown shot \(id)") }
            if seen.contains(id) { warnings.append("final_edit_order has duplicate shot \(id)") }
            seen.insert(id)
        }
        for p in broll {
            if let over = byId[p.overShotId] {
                if over.sceneType != .talkingHead { warnings.append("b-roll over_shot \(p.overShotId) is \(over.sceneType.rawValue), not a talking-head") }
            } else { warnings.append("b-roll over_shot \(p.overShotId) unknown") }
            if let src = byId[p.brollShotId] {
                if src.sceneType == .talkingHead { warnings.append("b-roll source \(p.brollShotId) is a talking-head") }
            } else { warnings.append("b-roll source \(p.brollShotId) unknown") }
            if p.overShotId == p.brollShotId { warnings.append("b-roll source equals the shot it covers (\(p.overShotId))") }
        }

        // ---- segments: one per shot, index fields verbatim + editorial fields derived ----
        let segments = index.shots.map { s -> Segment in
            let vo = voById[s.id]
            return Segment(id: s.id, startSeconds: s.startSeconds, endSeconds: s.endSeconds, sceneType: s.sceneType,
                           description: s.description, hookScore: s.hookScore, keep: kept.contains(s.id),
                           trimToSeconds: clampTrim(trimById[s.id]?.trimToSeconds, start: s.startSeconds, end: s.endSeconds), voiceoverCandidate: vo != nil,
                           voiceoverReason: vo?.reason, confidence: s.confidence,
                           editNote: noteById[s.id]?.note ?? "", section: s.section, topic: s.topic)
        }

        // ---- broll_placements: shot ids ARE segment ids; relative offset copies through (no math).
        // DROP any b-roll over a reaction shot (bite/first_taste/verdict/peak_reaction) — the face is the payoff.
        let placements = broll.compactMap { p -> BrollPlacement? in
            if let over = byId[p.overShotId], over.reactionKind != .none {
                warnings.append("dropped b-roll over shot \(p.overShotId) — it's a \(over.reactionKind.rawValue) reaction (never-cover)")
                return nil
            }
            return BrollPlacement(overSegmentId: p.overShotId, brollSegmentId: p.brollShotId,
                                  startOffsetSeconds: p.startOffsetSeconds, durationSeconds: p.durationSeconds,
                                  reason: p.reason.isEmpty ? nil : p.reason)
        }

        let plan = EditPlan(
            videoSummary: decisions.videoSummary.isEmpty ? index.videoSummary : decisions.videoSummary,
            recommendedHook: decisions.recommendedHook,
            recommendedDuration: decisions.recommendedDuration,
            finalEditOrder: order,
            segments: segments,
            styleMatchNotes: decisions.styleMatchNotes.isEmpty ? nil : decisions.styleMatchNotes,
            brollPlacements: placements)
        return (plan, warnings)
    }

    /// Clamp a DECIDE trim to the shot's OWN window — an out-of-range trim (e.g. DECIDE reaching for a reaction
    /// that's actually in the NEXT shot) becomes nil = play to the natural end. Deterministic safety net.
    private static func clampTrim(_ trim: Double?, start: Double, end: Double) -> Double? {
        guard let trim, trim > start + 0.05, trim < end - 0.05 else { return nil }
        return trim
    }
}

#if DEBUG
extension EditPlanAdapter {
    /// Self-check: a 2-shot index + decisions (order [0], b-roll over the talking-head ← the food shot) →
    /// 2 segments, both kept (shot 1 is a b-roll source), one b-roll placement, zero warnings. Logs ✅/❌.
    @discardableResult
    static func selfCheck() -> Bool {
        func shot(_ id: Int, _ type: SceneType) -> Shot {
            Shot(id: id, startSeconds: Double(id), endSeconds: Double(id) + 1, sceneType: type, description: "",
                 depictsSubject: type == .foodCloseup ? "Chicken Sandwich" : "", alsoVisible: [], hasSpeech: true,
                 section: .middle, topic: "Chicken Sandwich", hookScore: 5, reactionKind: .none, qualityFlags: [], confidence: 1)
        }
        let index = ContentIndex(durationSeconds: 2, videoSummary: "x", shots: [shot(0, .talkingHead), shot(1, .foodCloseup)], talkSpans: [])
        let decisions = EditDecisions(recommendedDuration: 2, recommendedHook: "open", hookId: 0, coldOpen: [0],
                                      finalEditOrder: [0], trims: [], voiceovers: [],
                                      brollPlacements: [.init(overShotId: 0, brollShotId: 1, startOffsetSeconds: 0.2, durationSeconds: 0.5, reason: "show food")],
                                      editNotes: [], styleMatchNotes: "", videoSummary: "")
        let (plan, warnings) = adapt(index: index, decisions: decisions)
        let keptCount = plan.segments.filter { $0.keep }.count
        let ok = plan.segments.count == 2 && keptCount == 2 && plan.brollPlacements.count == 1
            && plan.finalEditOrder == [0] && warnings.isEmpty
        Log.app(ok ? "✅ EditPlanAdapter.selfCheck passed (2 segments, both kept, 1 broll, 0 warnings)"
                   : "❌ EditPlanAdapter.selfCheck FAILED — segs \(plan.segments.count), kept \(keptCount), broll \(plan.brollPlacements.count), warnings \(warnings)")
        return ok
    }
}
#endif
