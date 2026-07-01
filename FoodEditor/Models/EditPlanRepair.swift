import Foundation

/// Deterministic, code-side repair of the **b-roll source-not-kept** failure — the one the lab proved is
/// (a) real and (b) *intermittent*, so a prompt rule can only lower its odds. This GUARANTEES it instead:
/// after Gemini answers, any b-roll overlay whose source clip is cut (or a talking-head, or the same clip
/// it covers) is **re-pointed to a kept, non-talking-head clip that depicts the same thing** — preferring a
/// clip of the same topic the speaker is talking about. If nothing valid exists to re-point to, the
/// placement is dropped (same as `EditPlanStore.seededLane` would have done, but now recorded).
///
/// Pure: returns a new `EditPlan` + a human-readable list of what it changed. The caller still validates
/// the ORIGINAL plan first, so we keep measuring how often the model breaks the rule (see AnalysisCoordinator).
enum EditPlanRepair {

    static func repairBroll(_ plan: EditPlan) -> (plan: EditPlan, actions: [String]) {
        guard !plan.brollPlacements.isEmpty else { return (plan, []) }
        let byId = Dictionary(plan.segments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Candidate pool: kept, visual (non-talking-head) clips we can show over a face.
        let keptVisual = plan.segments.filter { $0.keep && $0.sceneType != .talkingHead }

        /// Best kept visual clip whose topic matches `topic` (highest hook score wins), excluding `overId`.
        func bestMatch(topic: String, excluding overId: Int) -> Segment? {
            guard !topic.isEmpty else { return nil }
            return keptVisual
                .filter { $0.id != overId && $0.topic.caseInsensitiveCompare(topic) == .orderedSame }
                .max { $0.hookScore < $1.hookScore }
        }
        /// Last-resort: any kept visual clip, preferring food close-ups, then by hook score.
        func anyVisual(excluding overId: Int) -> Segment? {
            keptVisual.filter { $0.id != overId }.max { a, b in
                func rank(_ s: Segment) -> Double { (s.sceneType == .foodCloseup ? 100 : 0) + s.hookScore }
                return rank(a) < rank(b)
            }
        }

        var actions: [String] = []
        var repaired: [BrollPlacement] = []

        for p in plan.brollPlacements {
            let src = byId[p.brollSegmentId]
            let valid = src != nil && src!.keep && src!.sceneType != .talkingHead && p.brollSegmentId != p.overSegmentId
            if valid { repaired.append(p); continue }

            // Why was it broken? (for the log)
            let why = src == nil ? "missing"
                : (src!.keep == false ? "cut (keep:false)"
                : (src!.sceneType == .talkingHead ? "talking-head"
                : "same as over-segment"))

            // Re-point: prefer a kept clip of the topic being TALKED ABOUT (the over-segment's topic), then
            // the original source's topic, then any kept visual.
            let overTopic = byId[p.overSegmentId]?.topic ?? ""
            let srcTopic = src?.topic ?? ""
            let target = bestMatch(topic: overTopic, excluding: p.overSegmentId)
                ?? bestMatch(topic: srcTopic, excluding: p.overSegmentId)
                ?? anyVisual(excluding: p.overSegmentId)

            if let target {
                repaired.append(BrollPlacement(overSegmentId: p.overSegmentId, brollSegmentId: target.id,
                                               startOffsetSeconds: p.startOffsetSeconds,
                                               durationSeconds: p.durationSeconds, reason: p.reason))
                actions.append("over seg \(p.overSegmentId): source \(p.brollSegmentId) was \(why) → re-pointed to seg \(target.id) [\(target.sceneType.rawValue), topic \"\(target.topic)\"]")
            } else {
                actions.append("over seg \(p.overSegmentId): source \(p.brollSegmentId) was \(why) → dropped (no kept visual clip to re-point to)")
            }
        }

        let newPlan = EditPlan(videoSummary: plan.videoSummary, recommendedHook: plan.recommendedHook,
                               recommendedDuration: plan.recommendedDuration, finalEditOrder: plan.finalEditOrder,
                               segments: plan.segments, styleMatchNotes: plan.styleMatchNotes,
                               brollPlacements: repaired)
        return (newPlan, actions)
    }
}

#if DEBUG
extension EditPlanRepair {
    /// Self-check: the captured failure (b-roll sources 3/18/19 cut while same-topic close-ups are kept)
    /// should re-point to kept clips and leave zero cut sources. Logs ✅/❌ on a debug launch.
    @discardableResult
    static func selfCheck() -> Bool {
        func seg(_ id: Int, _ type: SceneType, keep: Bool, topic: String, hook: Double = 5) -> Segment {
            Segment(id: id, startSeconds: Double(id), endSeconds: Double(id) + 1, sceneType: type,
                    description: "", hookScore: hook, keep: keep, trimToSeconds: nil,
                    voiceoverCandidate: false, voiceoverReason: nil, confidence: 1, editNote: "",
                    section: .middle, topic: topic)
        }
        let segs = [
            seg(3, .foodCloseup, keep: false, topic: "Chicken Sandwich"),   // cut source
            seg(4, .foodCloseup, keep: true,  topic: "Chicken Sandwich", hook: 9), // kept same-topic → target
            seg(26, .talkingHead, keep: true, topic: "Chicken Sandwich"),   // over (talking about chicken)
        ]
        let plan = EditPlan(videoSummary: "", recommendedHook: "", recommendedDuration: 0,
                            finalEditOrder: [26], segments: segs, styleMatchNotes: nil,
                            brollPlacements: [BrollPlacement(overSegmentId: 26, brollSegmentId: 3,
                                                             startOffsetSeconds: 1, durationSeconds: 2, reason: nil)])
        let (fixed, actions) = repairBroll(plan)
        let byId = Dictionary(fixed.segments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let stillBroken = fixed.brollPlacements.contains { byId[$0.brollSegmentId]?.keep == false }
        let rePointedToKeptSameTopic = fixed.brollPlacements.first?.brollSegmentId == 4
        let ok = !stillBroken && rePointedToKeptSameTopic && actions.count == 1
        Log.app(ok ? "✅ EditPlanRepair.selfCheck passed (re-pointed cut b-roll source → kept same-topic clip)"
                   : "❌ EditPlanRepair.selfCheck FAILED — \(actions)")
        return ok
    }
}
#endif
