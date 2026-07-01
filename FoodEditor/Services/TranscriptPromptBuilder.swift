import Foundation

/// Builds the **Audio Transcript Block** — prepended before the tested segmentation body
/// (`styleBlock + briefBlock + transcriptBlock + GeminiPrompt.editPlan`) so Gemini anchors its timestamps
/// to REAL spoken-word times instead of guessing. ALWAYS emits the EXACT video duration as a hard bound,
/// even when no speech was transcribed — that bound alone fights the timeline hallucination (a 131s video
/// read as 212s). Like the other builders, it does NOT touch the tested `GeminiPrompt.editPlan`.
///
/// When the analysis proxy is several raw clips STITCHED together, it also interleaves `--- CLIP N ---`
/// markers at the exact merged-timeline second each clip begins (from `VideoPreprocessor.sourceSpans`). Those
/// are DETERMINISTIC hard shot cuts — Flash's own segmentation is unstable, so handing it the real cut points
/// anchors shots to the actual boundaries instead of guesses. `clipStarts` is the start-second of every clip;
/// clip 1 starts at 0 (no marker) so only clips 2…N are marked.
enum TranscriptPromptBuilder {

    static func block(words: [TranscriptionService.Word], duration: Double, clipStarts: [Double] = []) -> String {
        let dur = String(format: "%.1f", duration)
        // Boundaries worth marking = clip starts after 0 (clip 1 begins at the video start). ≥1 of these means
        // the proxy is ≥2 stitched clips.
        let cuts = clipStarts.sorted().filter { $0 > 0.05 }
        let clipPreamble = cuts.isEmpty ? "" :
            "This video is \(cuts.count + 1) separate clips STITCHED together — each clip cut is marked \"--- CLIP N ---\" and is a HARD shot boundary (always start a new shot there).\n\n"

        // IMPORTANT: when no transcript is available, do NOT imply the video is silent — Gemini hears the
        // video's own audio track and understands speech from it. Telling it "no speech" makes it edit
        // silently and drop the talking. Keep the duration bound; point it at the video's own audio.
        let transcriptBody: String
        if words.isEmpty {
            let base = "(A separate transcript wasn't available for this run. The video DOES have spoken audio — listen to the video's own soundtrack to understand and time the speech. Every timestamp you output must still lie between 0 and \(dur) seconds.)"
            // Even with no transcript, still expose the clip cut points — they're the segmentation anchors.
            transcriptBody = cuts.isEmpty ? base : base + "\n\n" + cutMarkers(cuts)
        } else {
            transcriptBody = "TRANSCRIPT (timestamp = the second at which each line's first word is spoken):\n" + lines(words, cuts: cuts)
        }

        return """
        === AUDIO TRANSCRIPT — GROUND TRUTH FOR TIMING ===

        This video is EXACTLY \(dur) seconds long. HARD RULES (these override any guess from watching):
        - Every start_seconds, end_seconds and trim_to_seconds MUST be between 0 and \(dur). NEVER output a timestamp greater than \(dur).
        - Segments must tile the whole video 0 → \(dur)s with no gaps and no segment longer than 15 seconds.
        - Anchor every talking-segment boundary to the transcript times below; split talking on the sentence boundaries shown here, NEVER inside a line.
        - trim_to_seconds is where a clip STOPS playing — it MUST land at the END of a complete spoken sentence/phrase, NEVER at a time inside a word or mid-sentence. To make a clip shorter, end it at an EARLIER complete sentence; never chop someone off mid-thought. When unsure, let them finish the sentence.
        - Silent food / b-roll stretches won't appear in the transcript — infer those from the video, but they still must fall within 0 → \(dur)s.

        \(clipPreamble)\(transcriptBody)

        === END AUDIO TRANSCRIPT ===


        """
    }

    /// The clip-cut marker lines on their own (used when there's no transcript to interleave them into).
    private static func cutMarkers(_ cuts: [Double]) -> String {
        cuts.enumerated()
            .map { "--- CLIP \($0.offset + 2) · new recording, hard cut at \(String(format: "%.1f", $0.element))s ---" }
            .joined(separator: "\n")
    }

    /// Group words into readable lines, breaking on sentence-ending punctuation or ~12 words, each line
    /// tagged with the start time of its first word — the anchors Gemini snaps talking boundaries to. Clip-cut
    /// markers are merged in by timestamp (a marker sorts BEFORE a word-line at the same second).
    private static func lines(_ words: [TranscriptionService.Word], cuts: [Double] = []) -> String {
        var wordLines: [(t: Double, text: String)] = []
        var cur: [String] = []
        var lineStart: Double?
        func flush() {
            guard let s = lineStart, !cur.isEmpty else { return }
            wordLines.append((s, "[\(String(format: "%.1f", s))] " + cur.joined(separator: " ")))
            cur.removeAll(); lineStart = nil
        }
        for w in words {
            if lineStart == nil { lineStart = w.start }
            cur.append(w.text)
            let endsSentence = w.text.hasSuffix(".") || w.text.hasSuffix("?") || w.text.hasSuffix("!")
            if endsSentence || cur.count >= 12 { flush() }
        }
        flush()

        // Merge word-lines (order 1) and clip markers (order 0) by time — marker before the line at the same second.
        var items: [(t: Double, order: Int, text: String)] = wordLines.map { ($0.t, 1, $0.text) }
        for (i, c) in cuts.enumerated() {
            items.append((c, 0, "--- CLIP \(i + 2) · new recording, hard cut at \(String(format: "%.1f", c))s ---"))
        }
        items.sort { $0.t != $1.t ? $0.t < $1.t : $0.order < $1.order }
        return items.map(\.text).joined(separator: "\n")
    }
}
