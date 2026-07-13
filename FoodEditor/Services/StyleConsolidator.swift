import Foundation

/// Consolidates N≥2 per-video `StyleProfileRaw`s into one profile with a **model** call — semantic dedupe
/// ("we'll see y'all next time" ≡ "see you in the next one") is exactly what the pure-Swift exact-string
/// `StyleProfileRaw.merge` can't do. Division of labor (review-hardened):
///   - The MODEL owns language: dominant categoricals, merged wording, a cross-video `reveal_script`.
///   - The CODE owns arithmetic + trust: numeric averages are recomputed exactly as `merge` does, every
///     `seen_in` citation is clamped/verified and `evidenceCount` derived from it (models cite far more
///     reliably than they count), `core` is set to (evidence == N) — never trusted from the model — and
///     suppressed lines are filtered again code-side (belt-and-braces under the prompt's REJECTED LINES).
/// Never hard-fails: ANY error falls back to `StyleProfileRaw.merge` so a style learn can't die here.
/// Runs device-direct through the proxy's sync text op (`GeminiService.decide`) — cheap, idempotent, and
/// kill-recovery just re-runs it after re-polling the persisted extraction jobs.
enum StyleConsolidator {

    static let model = "gemini-pro-latest"   // rare call, user-facing reveal copy — quality over pennies

    // MARK: - prompt (static body mirrored VERBATIM in tools/promptlab/prompts/style-consolidate.txt —
    // the lab hard-fails on drift, so edit both together)

    static let promptBody = """
    You are consolidating N per-video style profiles of ONE food creator into a single style template.
    Each source profile was extracted from a different finished video by the same creator, using the JSON
    schema you see in the sources. Return ONLY one valid JSON object in that SAME schema — no prose, no
    markdown — with the additions described below.

    Rules:
    - Categorical fields: choose the DOMINANT pattern across the sources (what they usually do), not the
      single most-confident video. Where sources genuinely disagree, prefer "other" plus a _custom
      description of the range (e.g. "30s dish reviews, occasionally 60s multi-dish").
    - recurring_lines, signoff, rating_format: deduplicate by MEANING — "we'll see y'all next time" and
      "see you in the next one" are the SAME sign-off; keep the clearest verbatim quote as "quote". If a
      line has a varying slot across videos ("Day 12…", "Day 47…"), set "pattern" to the templated form
      with a placeholder and keep one verbatim example as "quote".
    - EVIDENCE — for every recurring_line, every habit_candidate, and every section beat, add
      "seen_in": an array of the source indices (0-based) that contain it. Count paraphrases of the same
      line/habit/beat as the same item, but ONLY cite a source that really contains it — if a line is
      absent from a source, that index must not appear. Do not invent consistency.
    - structure.sections: unify beats to FORMAT-LEVEL labels that apply to any future video (never this
      video's dishes or places — those go in the beat's "example"); merge same-meaning beats; keep one
      "example" per beat from any source.
    - habit_candidates: merge same-meaning habits, keep the most specific label/detail, 3-6 items ordered
      most-distinctive-first, each with its "kind" and "seen_in". At least 2 must be kind selection or
      verbal.
    - reveal_script: REWRITE it as a story of consistency across all N videos — second person, one
      sentence per line, 4-6 lines, quoting the creator's own words at least once. Be numerically honest:
      "in all three videos…", "two out of three times…". Never say "always" or "every video" unless the
      item's seen_in covers every source.
    - Numbers (lengths, ratios, confidence): give your best estimate; a separate system recomputes exact
      averages, so never agonize over arithmetic.
    """

    // MARK: - entry point

    /// Consolidate per-video profiles ON-DEVICE. `knownSignatures` = quotes the creator already confirmed
    /// (string reuse prevents paraphrase drift breaking code-side matching); `suppressed` = normalized keys
    /// the creator rejected (never re-emitted, even paraphrased). Never throws — falls back to `merge`.
    /// NB: the normal path now runs this SAME call server-side (see `consolidationSpec` — the proxy chains
    /// it when the last extraction lands, so the push fires at true completion); this stays as the
    /// fallback for old servers, failed chains, and any error in the chained result.
    static func consolidate(_ profiles: [StyleProfileRaw],
                            knownSignatures: [String] = [],
                            suppressed: [String] = []) async -> StyleProfileRaw {
        guard profiles.count > 1 else { return StyleProfileRaw.merge(profiles) }
        do {
            let prompt = buildPrompt(profiles: profiles, knownSignatures: knownSignatures, suppressed: suppressed)
            let raw = try await GeminiService.shared.decide(prompt: prompt, schema: schema, model: model)
            Log.blob(.gemini, "RAW CONSOLIDATED PROFILE (\(profiles.count) sources)", raw)
            let merged = try decodeConsolidated(fromRawModelText: raw, sources: profiles, suppressed: suppressed)
            Log.gemini("Consolidated \(profiles.count) profiles → \(merged.verbalStyle.recurringLines.count) lines, \(merged.habitCandidates.count) habits.")
            return merged
        } catch is CancellationError {
            return StyleProfileRaw.merge(profiles)
        } catch {
            Log.gemini("⚠️ Consolidation fell back to code merge: \(error.localizedDescription)")
            return StyleProfileRaw.merge(profiles)
        }
    }

    /// Shared trust layer over a raw consolidated response — parse + viability gate + the code-owned
    /// passes (verified `seen_in` evidence, exact numeric averages, suppression). Used by BOTH the
    /// on-device path above and the server-chained path (raw text awaited from the consolidation job).
    static func decodeConsolidated(fromRawModelText raw: String, sources: [StyleProfileRaw],
                                   suppressed: [String] = []) throws -> StyleProfileRaw {
        var merged = try StyleProfileRaw.parse(fromRawModelText: raw)
        guard !(merged.styleBrief.isEmpty && merged.confidence == 0) else {
            throw EditPlanParseError.decodeFailed("consolidated profile came back empty")
        }
        applySeenIn(fromRawModelText: raw, to: &merged, sources: sources)
        overrideNumerics(&merged, from: sources)
        enforceSuppression(&merged, suppressed: suppressed)
        return merged
    }

    // MARK: - prompt assembly

    private static func buildPrompt(profiles: [StyleProfileRaw], knownSignatures: [String], suppressed: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sourcesJSON = (try? encoder.encode(profiles)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return promptHeader(knownSignatures: knownSignatures, suppressed: suppressed)
            + "\n\n=== SOURCE PROFILES (JSON array — source index = array position, 0-based, N = \(profiles.count)) ===\n"
            + sourcesJSON
    }

    /// Everything above the sources section — shared verbatim by the on-device prompt and the
    /// server-chained payload template so the two paths send the model the SAME instructions.
    private static func promptHeader(knownSignatures: [String], suppressed: [String]) -> String {
        var p = promptBody
        let known = knownSignatures.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !known.isEmpty {
            p += "\n\nKNOWN SIGNATURES — these exact strings are already confirmed in the creator's template. When the same line appears in the sources, reuse the EXACT string given (do not re-quote a variant) — but ONLY for lines you actually find in a source; if a known signature does not appear in a source, do not list that source in its seen_in, and if it appears in no source, omit it entirely:\n"
                + known.map { "- \"\($0)\"" }.joined(separator: "\n")
        }
        let rejected = suppressed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !rejected.isEmpty {
            p += "\n\nREJECTED LINES — the creator said these are NOT their signature. Never output a recurring_line matching any of these, even paraphrased or partial:\n"
                + rejected.map { "- \"\($0)\"" }.joined(separator: "\n")
        }
        return p
    }

    // MARK: - server-chained consolidation (payload authored HERE, results substituted by the proxy)

    /// The token the proxy replaces with new-source i's extraction result — keep the literal format in
    /// lockstep with `substituteSources` in supabase/functions/gemini-proxy/index.ts.
    static func sourcePlaceholder(_ i: Int) -> String { "«VELA_SRC_\(i)»" }

    /// The COMPLETE consolidation request, authored at SUBMIT time — before the extractions exist — with
    /// `«VELA_SRC_i»` placeholders standing in for the N new per-video results. Refinements inline their
    /// base sources (known now) ahead of the placeholders, so source indices stay identical to the
    /// on-device path. The proxy substitutes each slot with that job's (fence-stripped) result and runs
    /// the call the moment the last extraction lands — the "style is ready" push then means the template
    /// is genuinely built. Shape: `{ payload: <generateContent body>, model: <text model> }`.
    static func consolidationSpec(newCount: Int, baseSources: [StyleProfileRaw] = [],
                                  knownSignatures: [String] = [], suppressed: [String] = []) -> [String: Any] {
        let total = baseSources.count + newCount
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let baseJSONs = baseSources.map { s in
            (try? encoder.encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
        let slots = baseJSONs + (0..<newCount).map { sourcePlaceholder($0) }
        let prompt = promptHeader(knownSignatures: knownSignatures, suppressed: suppressed)
            + "\n\n=== SOURCE PROFILES (JSON array — source index = array position, 0-based, N = \(total)) ===\n"
            + "[" + slots.joined(separator: ",") + "]"
        return ["payload": GeminiService.generatePayload(prompt: prompt, schema: schema), "model": model]
    }

    // MARK: - seen_in → evidenceCount (code-derived, spot-verified)

    /// Walk the raw response for `seen_in` arrays (they're NOT part of `StyleProfileRaw`) and derive
    /// evidence counts. Lines are verbatim by contract → each cited index is VERIFIED by normalized
    /// substring search over that source's lines/sign-off (unverifiable citations are dropped; if all drop,
    /// fall back to the clamped citation count). Habits/beats are legitimately re-worded by the semantic
    /// merge, so their citations are clamped/deduped but not text-verified.
    private static func applySeenIn(fromRawModelText raw: String, to merged: inout StyleProfileRaw, sources: [StyleProfileRaw]) {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let n = sources.count

        func citedIndices(_ item: [String: Any]) -> [Int]? {
            guard let arr = item["seen_in"] as? [Any] else { return nil }
            let ints = arr.compactMap { ($0 as? NSNumber)?.intValue }.filter { (0..<n).contains($0) }
            return Array(Set(ints)).sorted()
        }
        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func sourceContainsLine(_ idx: Int, key: String) -> Bool {
            guard !key.isEmpty else { return false }
            let vs = sources[idx].verbalStyle
            let haystacks = vs.recurringLines.flatMap { [norm($0.quote), norm($0.pattern ?? "")] } + [norm(vs.signoff)]
            return haystacks.contains { !$0.isEmpty && ($0.contains(key) || key.contains($0)) }
        }

        // recurring_lines — match model items to decoded items by order (same array), verify citations.
        if let vsObj = root["verbal_style"] as? [String: Any],
           let lineObjs = vsObj["recurring_lines"] as? [[String: Any]] {
            for i in merged.verbalStyle.recurringLines.indices where i < lineObjs.count {
                guard let cited = citedIndices(lineObjs[i]) else { continue }
                let key = merged.verbalStyle.recurringLines[i].key
                let verified = cited.filter { sourceContainsLine($0, key: key) }
                let count = !verified.isEmpty ? verified.count : max(1, min(cited.count, n))
                merged.verbalStyle.recurringLines[i].evidenceCount = count
            }
        }
        // habit_candidates — clamped citations only.
        if let habObjs = root["habit_candidates"] as? [[String: Any]] {
            for i in merged.habitCandidates.indices where i < habObjs.count {
                guard let cited = citedIndices(habObjs[i]) else { continue }
                merged.habitCandidates[i].evidenceCount = max(1, min(cited.count, n))
            }
        }
        // section beats — clamped citations; `core` is DERIVED (evidence == N), never the model's word.
        if let structObj = root["structure"] as? [String: Any],
           let secObjs = structObj["sections"] as? [[String: Any]] {
            for s in merged.structure.sections.indices where s < secObjs.count {
                let beatObjs = (secObjs[s]["beats"] as? [[String: Any]]) ?? []
                for b in merged.structure.sections[s].beats.indices where b < beatObjs.count {
                    guard let cited = citedIndices(beatObjs[b]) else { continue }
                    let count = max(1, min(cited.count, n))
                    merged.structure.sections[s].beats[b].evidenceCount = count
                    merged.structure.sections[s].beats[b].core = (count == n)
                }
            }
        }
    }

    // MARK: - deterministic numeric override (identical arithmetic to StyleProfileRaw.merge)

    private static func overrideNumerics(_ merged: inout StyleProfileRaw, from profiles: [StyleProfileRaw]) {
        func avg(_ f: (StyleProfileRaw) -> Double) -> Double {
            let xs = profiles.map(f).filter { $0 > 0 }
            return xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
        }
        merged.hook.opensWithinSeconds         = avg { $0.hook.opensWithinSeconds }
        merged.pacing.totalLengthSeconds       = avg { $0.pacing.totalLengthSeconds }
        merged.pacing.averageClipLengthSeconds = avg { $0.pacing.averageClipLengthSeconds }
        merged.voiceover.voiceoverRatio        = avg { $0.voiceover.voiceoverRatio }
        merged.confidence                      = avg { $0.confidence }
        let n = profiles.count
        for i in merged.verbalStyle.recurringLines.indices {
            merged.verbalStyle.recurringLines[i].evidenceCount = min(max(1, merged.verbalStyle.recurringLines[i].evidenceCount), n)
        }
        for i in merged.habitCandidates.indices {
            merged.habitCandidates[i].evidenceCount = min(max(1, merged.habitCandidates[i].evidenceCount), n)
        }
    }

    // MARK: - suppression (belt-and-braces under the prompt's REJECTED LINES)

    private static func enforceSuppression(_ merged: inout StyleProfileRaw, suppressed: [String]) {
        guard !suppressed.isEmpty else { return }
        let keys = Set(suppressed.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        merged.verbalStyle.recurringLines.removeAll { line in
            let k = line.key
            return keys.contains { !$0.isEmpty && (k.contains($0) || $0.contains(k)) }
        }
        if keys.contains(where: { !$0.isEmpty && merged.verbalStyle.signoff.lowercased().contains($0) }) {
            merged.verbalStyle.signoff = ""
        }
    }

    // MARK: - responseSchema (constrained decoding — the cheapest structured-output win in the plan)

    /// Consolidation schema: the profile shape + the consolidation-only `seen_in` citation arrays.
    static var schema: [String: Any] { profileSchema(seenIn: true) }

    /// Extraction schema: same shape, NO `seen_in`. Validated on the creator's real videos (2026-07-11):
    /// constrained decoding doubled recurring-line recall (the intro formula was found in all 3 videos vs
    /// 1 of 3 schema-less), stabilized run-to-run output, and locked the role enum (no more "intro" drift).
    static var extractionSchema: [String: Any] { profileSchema(seenIn: false) }

    /// Google-schema mirror of the profile JSON (same helper idiom as `DecidePrompt.schema`); mirrors
    /// tools/promptlab/style-schema.json.
    private static func profileSchema(seenIn includeSeenIn: Bool) -> [String: Any] {
        func obj(_ props: [String: Any], _ order: [String], required: [String]? = nil) -> [String: Any] {
            ["type": "OBJECT", "properties": props, "propertyOrdering": order, "required": required ?? order]
        }
        func arr(_ items: [String: Any]) -> [String: Any] { ["type": "ARRAY", "items": items] }
        func enumStr(_ values: [String]) -> [String: Any] { ["type": "STRING", "enum": values] }
        func enumStrN(_ values: [String]) -> [String: Any] { ["type": "STRING", "enum": values, "nullable": true] }
        let str: [String: Any] = ["type": "STRING"]
        let strN: [String: Any] = ["type": "STRING", "nullable": true]
        let num: [String: Any] = ["type": "NUMBER"]
        let boolean: [String: Any] = ["type": "BOOLEAN"]
        let seenIn = arr(["type": "INTEGER"])
        /// Append seen_in to an item schema when consolidating.
        func withSeenIn(_ props: [String: Any], _ order: [String], required: [String]) -> [String: Any] {
            var p = props; var o = order; var r = required
            if includeSeenIn { p["seen_in"] = seenIn; o.append("seen_in"); r.append("seen_in") }
            return obj(p, o, required: r)
        }

        let montage = obj(["is_montage": boolean, "source": strN, "clip_count_estimate": num, "avg_clip_seconds": num],
                          ["is_montage", "source", "clip_count_estimate", "avg_clip_seconds"], required: ["is_montage"])
        let hook = obj(["type": enumStr(["food-closeup", "bite-reaction", "talking-head-claim", "text-on-screen",
                                         "plating", "action", "pov", "social-proof-montage", "other"]),
                        "type_custom": strN, "opens_within_seconds": num, "has_text_overlay": boolean,
                        "description": str, "montage": montage],
                       ["type", "type_custom", "opens_within_seconds", "has_text_overlay", "description", "montage"],
                       required: ["type", "opens_within_seconds", "has_text_overlay", "description", "montage"])
        let videoFormat = obj(["type": str, "type_custom": strN, "notes": str], ["type", "type_custom", "notes"], required: ["type", "notes"])
        let pacing = obj(["total_length_seconds": num, "average_clip_length_seconds": num,
                          "cut_style": enumStr(["fast-punchy", "medium", "slow-lingering", "other"]),
                          "cut_style_custom": strN, "pacing_notes": str],
                         ["total_length_seconds", "average_clip_length_seconds", "cut_style", "cut_style_custom", "pacing_notes"],
                         required: ["total_length_seconds", "average_clip_length_seconds", "cut_style", "pacing_notes"])
        let voiceover = obj(["primary_mode": enumStr(["mostly-voiceover-over-broll", "mostly-talking-to-camera", "even-mix", "other"]),
                             "primary_mode_custom": strN, "voiceover_ratio": num,
                             "talks_to_camera": boolean, "notes": str],
                            ["primary_mode", "primary_mode_custom", "voiceover_ratio", "talks_to_camera", "notes"],
                            required: ["primary_mode", "voiceover_ratio", "talks_to_camera", "notes"])
        let broll = obj(["amount": enumStr(["heavy", "moderate", "minimal"]), "usage": str, "usage_custom": strN,
                         "favored_shots": arr(str), "notes": str],
                        ["amount", "usage", "usage_custom", "favored_shots", "notes"],
                        required: ["amount", "usage", "favored_shots", "notes"])
        let beat = withSeenIn(["label": str, "time_hint": str, "example": strN],
                              ["label", "time_hint", "example"], required: ["label", "time_hint"])
        let section = obj(["section": enumStr(["intro", "middle", "end"]), "purpose": str, "beats": arr(beat)],
                          ["section", "purpose", "beats"])
        let structure = obj(["arc": arr(str), "sections": arr(section), "notes": str], ["arc", "sections", "notes"])
        let textGraphics = obj(["uses_text_overlays": boolean, "text_style": str, "text_style_custom": strN, "amount": str],
                               ["uses_text_overlays", "text_style", "text_style_custom", "amount"],
                               required: ["uses_text_overlays", "text_style", "amount"])
        let audio = obj(["bed": str, "bed_custom": strN, "keeps_natural_food_sounds": boolean, "notes": str],
                        ["bed", "bed_custom", "keeps_natural_food_sounds", "notes"],
                        required: ["bed", "keeps_natural_food_sounds", "notes"])
        let closing = obj(["type": enumStr(["verdict", "rating", "call-to-action", "final-beauty-shot", "abrupt", "other"]),
                           "type_custom": strN, "description": str],
                          ["type", "type_custom", "description"], required: ["type", "description"])
        let line = withSeenIn(["quote": str,
                               "where_used": enumStr(["hook", "verdict", "sign-off", "transition", "throughout"]),
                               "medium": enumStr(["spoken", "text-overlay"]),
                               "pattern": strN,
                               "position": enumStr(["opening", "mid", "closing"]),
                               "delivery_note": str, "likely_habit": num],
                              ["quote", "where_used", "medium", "pattern", "position", "delivery_note", "likely_habit"],
                              required: ["quote", "where_used", "medium", "position", "delivery_note", "likely_habit"])
        let verbal = obj(["tone": str, "pov": str, "rating_format": strN,
                          "rating_scope": enumStrN(["overall", "per-item", "both"]), "signoff": strN,
                          "recurring_lines": arr(line)],
                         ["tone", "pov", "rating_format", "rating_scope", "signoff", "recurring_lines"],
                         required: ["tone", "pov", "recurring_lines"])
        let habit = withSeenIn(["label": str, "detail": str,
                                "kind": enumStr(["selection", "verbal", "supplied-footage", "visual-effect"]),
                                "likely_habit": num, "times_seen_in_video": num],
                               ["label", "detail", "kind", "likely_habit", "times_seen_in_video"],
                               required: ["label", "detail", "kind", "likely_habit", "times_seen_in_video"])
        let move = obj(["move": str, "likely_habit": num], ["move", "likely_habit"])

        let order = ["style_brief", "video_format", "hook", "pacing", "voiceover_vs_oncamera", "broll",
                     "structure", "text_and_graphics", "audio", "closing", "verbal_style", "habit_candidates",
                     "reveal_script", "signature_moves", "anything_unusual", "scene_types_present", "confidence"]
        return obj([
            "style_brief": str, "video_format": videoFormat, "hook": hook, "pacing": pacing,
            "voiceover_vs_oncamera": voiceover, "broll": broll, "structure": structure,
            "text_and_graphics": textGraphics, "audio": audio, "closing": closing,
            "verbal_style": verbal, "habit_candidates": arr(habit), "reveal_script": arr(str),
            "signature_moves": arr(move), "anything_unusual": strN, "scene_types_present": arr(str),
            "confidence": num
        ], order, required: order.filter { $0 != "anything_unusual" })
    }
}
