import Foundation

/// Deterministic NORMALIZER for a PERCEIVE `ContentIndex` — the "code fixes mechanical, AI owns content"
/// pass that runs BEFORE DECIDE (so DECIDE sees clean ids). It: splits any shot longer than 15s into
/// back-to-back ≤15s pieces, drops zero/negative-length talk_spans, clamps everything to `[0, duration]`,
/// and re-numbers shots `0..n-1` ascending by start. This fixes the known PERCEIVE residue the lab found
/// (a stray >15s shot, a rare zero-length span) without the AI re-running. Pure + deterministic.
enum ContentIndexNormalizer {
    static let maxShot = 15.0
    static let tol = 0.25

    static func normalize(_ index: ContentIndex) -> (index: ContentIndex, actions: [String]) {
        let dur = index.durationSeconds > 0 ? index.durationSeconds : (index.shots.map(\.endSeconds).max() ?? 0)
        var actions: [String] = []

        // 1) split over-long shots into ≤15s pieces; clamp every shot to [0, dur].
        var pieces: [Shot] = []
        for s in index.shots.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let start = max(0, min(s.startSeconds, dur))
            let end = max(start, min(s.endSeconds, dur))
            let len = end - start
            if len > maxShot + tol {
                let n = Int((len / maxShot).rounded(.up))
                let step = len / Double(n)
                for i in 0..<n {
                    let a = start + Double(i) * step
                    let b = (i == n - 1) ? end : a + step
                    pieces.append(s.with(id: 0, startSeconds: a, endSeconds: b))
                }
                actions.append("split shot \(s.id) (\(fmt(len))s) into \(n) ≤15s pieces")
            } else {
                pieces.append(s.with(id: 0, startSeconds: start, endSeconds: end))
            }
        }
        // 2) re-number 0..n-1 ascending by start (DECIDE references these ids).
        pieces.sort { $0.startSeconds < $1.startSeconds }
        let shots = pieces.enumerated().map { idx, s in s.with(id: idx, startSeconds: s.startSeconds, endSeconds: s.endSeconds) }

        // 3) drop zero/negative-length spans + clamp to [0, dur].
        var spans: [TalkSpan] = []
        var dropped = 0
        for sp in index.talkSpans {
            let a = max(0, min(sp.startSeconds, dur))
            let b = max(a, min(sp.endSeconds, dur))
            if b - a < 0.05 { dropped += 1; continue }
            spans.append(TalkSpan(startSeconds: a, endSeconds: b, spokenText: sp.spokenText,
                                  referencesSubject: sp.referencesSubject, alsoReferences: sp.alsoReferences,
                                  isToCamera: sp.isToCamera))
        }
        if dropped > 0 { actions.append("dropped \(dropped) zero-length talk_span(s)") }

        let out = ContentIndex(durationSeconds: dur, videoSummary: index.videoSummary, shots: shots, talkSpans: spans)
        return (out, actions)
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.1f", d) }
}

#if DEBUG
extension ContentIndexNormalizer {
    /// Self-check: a 30s shot splits into two ≤15s pieces; a normal shot is untouched; a zero-length span
    /// is dropped; shots re-number 0..n-1. Logs ✅/❌ on a debug launch.
    @discardableResult
    static func selfCheck() -> Bool {
        func shot(_ id: Int, _ a: Double, _ b: Double) -> Shot {
            Shot(id: id, startSeconds: a, endSeconds: b, sceneType: .talkingHead, description: "", depictsSubject: "",
                 alsoVisible: [], hasSpeech: true, section: .middle, topic: "", hookScore: 0, reactionKind: .none,
                 qualityFlags: [], confidence: 1)
        }
        let index = ContentIndex(durationSeconds: 40, videoSummary: "", shots: [shot(5, 0, 30), shot(9, 30, 35)],
                                 talkSpans: [TalkSpan(startSeconds: 10, endSeconds: 10, spokenText: "x",
                                                      referencesSubject: "", alsoReferences: [], isToCamera: true)])
        let (out, actions) = normalize(index)
        let over15 = out.shots.contains { $0.endSeconds - $0.startSeconds > 15.25 }
        let ids = out.shots.map(\.id)
        let ok = out.shots.count == 3 && !over15 && ids == Array(0..<out.shots.count) && out.talkSpans.isEmpty && actions.count == 2
        Log.app(ok ? "✅ ContentIndexNormalizer.selfCheck passed (30s shot → 2 pieces, ids 0..n, zero-span dropped)"
                   : "❌ ContentIndexNormalizer.selfCheck FAILED — shots \(out.shots.count), over15 \(over15), spans \(out.talkSpans.count), \(actions)")
        return ok
    }
}
#endif
