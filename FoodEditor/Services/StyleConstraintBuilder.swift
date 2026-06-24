import Foundation

/// Builds **Part A** of the connector — the Style Injection Block prepended to the segmentation body
/// (`GeminiPrompt.editPlan`) when a creator has an active style. Fills the block from the active
/// `StyleTemplate`'s machine profile, plus the editable surface the creator owns: the recipe (as the arc),
/// the enabled toggles ("habits to honor"), and the free notes field. Returns `""` when there's no active
/// template — so the prompt is exactly the original generic version.
enum StyleConstraintBuilder {

    static func block(for template: StyleTemplate?) -> String {
        guard let t = template else { return "" }
        let p = t.profile

        let hook = nonEmpty(p.hook.resolved, "a strong visual moment")
        let cut = String(format: "%.1f", max(0, p.pacing.averageClipLengthSeconds))
        let total = Int(max(0, p.pacing.totalLengthSeconds).rounded())
        let opens = Int(max(0, p.hook.opensWithinSeconds).rounded())
        let cutStyle = nonEmpty(p.pacing.cutStyleResolved, "their usual pacing")
        let vo = String(format: "%.2f", min(1, max(0, p.voiceover.voiceoverRatio)))
        let brollAmount = nonEmpty(p.broll.amount, "some")
        let brollUsage = nonEmpty(p.broll.usageResolved, "as needed")
        let favShots = p.broll.favoredShotsText
        let brollPct = Int((min(1, max(0, p.broll.heaviness)) * 100).rounded())
        let tgAmount = nonEmpty(p.textAndGraphics.amount, "some")
        let tgStyle = nonEmpty(p.textAndGraphics.textStyleResolved, "their usual style")
        let closing = nonEmpty(p.closing.resolved, "their usual closing")
        let moves = nonEmpty(p.signatureMoves.map(\.move).filter { !$0.isEmpty }.joined(separator: "; "), "none noted")
        let unusual = nonEmpty(p.anythingUnusual ?? "", "none")

        // Recipe (editable beats) drives the arc when present; else fall back to the profile's arc.
        let arc: String = t.beats.isEmpty
            ? p.structure.arcText
            : t.beats.map { "\($0.chip) (\($0.t)): \($0.text)" }.joined(separator: " → ")

        // SECTION MAP — the learned intro/middle/end structure to recreate. Falls back to the flat arc
        // line for legacy templates that predate section learning.
        let sectionMap: String = {
            let secs = p.structure.sections.filter { !$0.beats.isEmpty || !$0.purpose.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !secs.isEmpty else {
                return "- Typical arc: \(arc). → Order final_edit_order to follow this narrative shape where the footage allows."
            }
            let rank = ["intro": 0, "middle": 1, "end": 2]
            let ordered = secs.sorted { (rank[$0.section.lowercased()] ?? 9) < (rank[$1.section.lowercased()] ?? 9) }
            let beatLines = ordered.map { s -> String in
                let core  = s.beats.filter { $0.core }.map(\.label).filter { !$0.isEmpty }
                let extra = s.beats.filter { !$0.core }.map(\.label).filter { !$0.isEmpty }
                var parts: [String] = []
                let purpose = s.purpose.trimmingCharacters(in: .whitespaces)
                if !purpose.isEmpty { parts.append(purpose) }
                if !core.isEmpty    { parts.append("always include: \(core.joined(separator: ", "))") }
                if !extra.isEmpty   { parts.append("include if present: \(extra.joined(separator: ", "))") }
                return "  • \(s.section.uppercased()) — \(parts.joined(separator: "; "))"
            }
            return (["- SECTION MAP — recreate this creator's structure. Tag every segment's section and rebuild the video intro → middle → end:"]
                    + beatLines
                    + ["  For each section, keep the raw segments that fill its beats — the INTRO especially (the place / name / what they ordered / an establishing shot); never drop those as slow or filler. Order final_edit_order by section. If a listed beat isn't in the footage, don't fabricate it — say so in style_match_notes."])
                .joined(separator: "\n")
        }()

        // Enabled toggles (defaults + custom) — honored directives the creator confirmed.
        let onHabits = t.habits.filter { $0.on && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        let habitsSection: String = onHabits.isEmpty ? "" : "\n\nHABITS THE CREATOR KEPT ON (honor these wherever the footage allows):\n" + onHabits.map { h in
            if let d = h.detail, !d.isEmpty { return "- \(h.label) — \(d)" }
            return "- \(h.label)"
        }.joined(separator: "\n")

        let trimmedNotes = t.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesSection = trimmedNotes.isEmpty ? "" : "\n\nEXTRA NOTES FROM THE CREATOR (honor these):\n\(trimmedNotes)"

        return """
        === THIS CREATOR'S EDITING STYLE — EDIT TO MATCH ===

        You are editing for a specific creator. Below is their learned editing style. Your segmentation and edit decisions should make the final video feel like THEY made it, not like a generic edit. Apply this style as far as the available raw footage allows — match it where the footage supports it, and where the footage lacks what the style calls for, get as close as the available segments allow rather than inventing anything.

        STYLE BRIEF (read this first — it's the gist):
        \(nonEmpty(t.summary, "A clean, appetizing edit that feels like this creator."))

        KEY STYLE TARGETS (translate these tendencies into your per-segment decisions):
        - Preferred hook: \(hook) — they open within ~\(opens)s. → Choose a hook segment of this type if one exists; give it the top of final_edit_order. If no such segment exists, pick the closest high-impact opener available.
        - Pacing: they average ~\(cut)s per clip (\(cutStyle)), total length ~\(total)s. → This is their VISUAL rhythm — created by cutting between shots and laying quick b-roll, NOT by cutting people off mid-sentence. Do NOT use trim_to_seconds to pull talking toward this average; let a talking segment run as long as the thought needs. You may use the total length as a SOFT guide for which segments to keep, but completeness of the message wins — never drop or shorten a segment that's needed to land the point.
        - Voiceover ratio: \(vo) (0 = always face on camera, 1 = always voice over b-roll). → The higher this number, the more aggressively you should mark qualifying talking-head segments as voiceover_candidate (still respecting the strict voiceover rules in the body below).
        - B-roll: \(brollAmount) amount, used \(brollUsage); favored shots: \(favShots). → Aim for roughly \(brollPct)% of the final video covered by b-roll overlays (the broll_placements list), and prefer these shot types when choosing each b-roll and for voiceover_reason.
        \(sectionMap)
        - Text/graphics habit: \(tgAmount) (\(tgStyle)). → Note in edit_note where their usual overlays (e.g. dish names) would go; you are not creating graphics, just flagging placement.
        - Closing: \(closing). → Try to end final_edit_order on a segment that fits this closing style.
        - Signature moves: \(moves). → If the footage contains a moment that lets you honor one of these, do so and mention it in the relevant edit_note.
        - Anything unusual: \(unusual).\(habitsSection)\(notesSection)

        PRIORITY RULE: When the style and good general editing conflict, favor the creator's style — it's why they're using this tool. The ONE exception: never violate the voiceover rules or the segmentation rules in the body below; those are hard constraints, the style is a strong preference on top of them.

        === END STYLE BLOCK ===


        """
    }

    private static func nonEmpty(_ s: String, _ fallback: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }
}
