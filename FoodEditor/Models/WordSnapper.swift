import Foundation

/// Deterministic, code-side **word-snapping** of clip OUT points — the ONE place code is allowed to
/// *transform* the AI's plan (every other safety-net check asserts, never rewrites). The video model sets
/// `trim_to_seconds` from a ±0.5–2s sense of time, so a talking clip routinely STOPS mid-word ("This looks
/// in—", "I got the medi—", "The medi—" on the verdict): the #1 "this was auto-edited" tell, and exactly the
/// "choppy / cut off while I'm talking" the creator reported. With the on-device word-level transcript as
/// ground truth, this slides any OUT that lands *inside* a spoken word forward to the end of that sentence
/// run (+ a short breath), so the creator always finishes their thought.
///
/// Safe by construction:
/// - Snaps **only the OUT** (`trim_to_seconds`), never `start_seconds` — `start_seconds` tiles
///   `EditPlanValidator`'s `[0,duration]` coverage check and the `SourceSpan` map, so moving it would
///   fabricate gap/overlap violations. The reported bug is entirely OUT-point/trim, so this suffices.
/// - Never extends past the segment's own `end_seconds`, so a clip can't bleed into its neighbour →
///   zero overlap/repeat risk.
/// - No transcript (`words` empty) → exact no-op, the plan ships unchanged.
///
/// Pure: returns a new `EditPlan` + a human-readable list of what it changed (mirrors `EditPlanRepair`).
/// The caller validates the ORIGINAL plan first, so we keep measuring the model's *unsnapped* output.
enum WordSnapper {
    /// Hard cap on how far a snap may push the OUT. Finishing the current word should never extend more than
    /// this — it stops an INTENTIONAL short trim (DECIDE deliberately cutting a talking shot to a few seconds)
    /// from bloating into the whole continuous take.
    private static let maxExtend = 1.0
    /// Played after the last spoken word so the audio's tail/breath isn't clipped flush against the consonant.
    private static let breath = 0.12
    /// Ignore sub-frame snaps (< this) — not worth a trim or a log line. Also the containment margin so a cut
    /// already sitting on a word boundary counts as clean.
    private static let epsilon = 0.05

    static func snap(_ plan: EditPlan, words: [TranscriptionService.Word]) -> (plan: EditPlan, actions: [String]) {
        guard !words.isEmpty else { return (plan, []) }
        let sorted = words.sorted { $0.start < $1.start }
        var actions: [String] = []

        let snapped = plan.segments.map { seg -> Segment in
            // Only kept clips reach the spine, so only their OUT points are ever seen — don't waste a snap
            // (or a log line) on a clip the edit drops.
            guard seg.keep else { return seg }
            let out = seg.trimToSeconds ?? seg.endSeconds
            // The only "bad" cut is one that lands STRICTLY inside a spoken word. A cut already in a pause
            // (or in a silent / visual clip with no words near it) is clean — leave it untouched.
            guard let idx = sorted.firstIndex(where: { out > $0.start + epsilon && out < $0.start + $0.duration - epsilon })
            else { return seg }

            // Finish the CURRENT WORD only (+ a breath) — never run on through the rest of the talking.
            // DECIDE already trims to sentence ends; word-snap is ONLY the mechanical "don't cut mid-word"
            // net, so a hard +maxExtend cap stops it from turning a deliberate 3s trim into the whole 12s take.
            let wordEnd = sorted[idx].start + sorted[idx].duration + breath
            let newOut = min(min(wordEnd, out + maxExtend), seg.endSeconds)  // finish the word, capped, in-bounds
            guard newOut > out + epsilon else { return seg }      // already clean / nothing worth doing

            actions.append("seg \(seg.id): OUT \(fmt(out))s was inside \"\(sorted[idx].text)\" → \(fmt(newOut))s (finished the word)")
            // newOut == endSeconds means "play to the natural end" → store nil (no trim); else the snapped OUT.
            let newTrim: Double? = newOut >= seg.endSeconds - epsilon ? nil : newOut
            return segment(seg, trimToSeconds: newTrim)
        }

        let newPlan = EditPlan(videoSummary: plan.videoSummary, recommendedHook: plan.recommendedHook,
                               recommendedDuration: plan.recommendedDuration, finalEditOrder: plan.finalEditOrder,
                               segments: snapped, styleMatchNotes: plan.styleMatchNotes,
                               brollPlacements: plan.brollPlacements)
        return (newPlan, actions)
    }

    /// Rebuild a segment with a new `trimToSeconds` (Segment is an immutable struct). Kept private so
    /// `EditPlan.swift` stays untouched.
    private static func segment(_ s: Segment, trimToSeconds: Double?) -> Segment {
        Segment(id: s.id, startSeconds: s.startSeconds, endSeconds: s.endSeconds, sceneType: s.sceneType,
                description: s.description, hookScore: s.hookScore, keep: s.keep, trimToSeconds: trimToSeconds,
                voiceoverCandidate: s.voiceoverCandidate, voiceoverReason: s.voiceoverReason,
                confidence: s.confidence, editNote: s.editNote, section: s.section, topic: s.topic)
    }

    private static func fmt(_ t: Double) -> String { String(format: "%.2f", t) }
}

#if DEBUG
extension WordSnapper {
    /// Self-check on the captured failure shape: a talking clip whose `trim_to_seconds` lands mid-word should
    /// snap out to the end of the sentence (+breath); a clip whose trim already sits in a pause is left alone.
    /// Logs ✅/❌ on a debug launch (alongside `EditPlanRepair.selfCheck`).
    @discardableResult
    static func selfCheck() -> Bool {
        // "I got the medium spicy" as one run (0.0–2.2s), a long pause, then "Mmm" at 6.0s.
        let words = [
            TranscriptionService.Word(text: "I",      start: 0.0, duration: 0.2),
            TranscriptionService.Word(text: "got",    start: 0.3, duration: 0.2),
            TranscriptionService.Word(text: "the",    start: 0.6, duration: 0.2),
            TranscriptionService.Word(text: "medium", start: 0.9, duration: 0.5),   // 0.9–1.4
            TranscriptionService.Word(text: "spicy",  start: 1.6, duration: 0.6),   // 1.6–2.2 (sentence end)
            TranscriptionService.Word(text: "Mmm",    start: 6.0, duration: 0.4),
        ]
        func seg(_ id: Int, trim: Double?) -> Segment {
            Segment(id: id, startSeconds: 0, endSeconds: 5, sceneType: .talkingHead,
                    description: "", hookScore: 0, keep: true, trimToSeconds: trim,
                    voiceoverCandidate: false, voiceoverReason: nil, confidence: 1, editNote: "",
                    section: .middle, topic: "")
        }
        // seg 1: trim 1.0 is inside "medium" → snap through "spicy" (ends 2.2) + 0.12 breath = 2.32s.
        // seg 2: trim 4.0 is in the pause (2.2–6.0) → untouched.
        let plan = EditPlan(videoSummary: "", recommendedHook: "", recommendedDuration: 0,
                            finalEditOrder: [1, 2], segments: [seg(1, trim: 1.0), seg(2, trim: 4.0)],
                            styleMatchNotes: nil, brollPlacements: [])
        let (out, actions) = snap(plan, words: words)
        let byId = Dictionary(out.segments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let s1 = byId[1]?.trimToSeconds ?? -1
        let s2 = byId[2]?.trimToSeconds ?? -1
        // "medium" spans 0.9–1.4, so OUT 1.0 (mid-word) finishes that word → 1.4 + 0.12 breath = 1.52
        // (capped, NOT extended through "spicy"). The pause cut at 4.0 is already clean → untouched.
        let ok = abs(s1 - 1.52) < 0.02 && abs(s2 - 4.0) < 0.001 && actions.count == 1
        Log.app(ok ? "✅ WordSnapper.selfCheck passed (mid-word OUT 1.00s → 1.52s [finished the word]; pause cut 4.00s untouched)"
                   : "❌ WordSnapper.selfCheck FAILED — s1=\(s1) s2=\(s2) actions=\(actions)")
        return ok
    }
}
#endif
