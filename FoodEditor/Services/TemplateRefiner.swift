import Foundation

// ============================================================================
// MARK: - TemplateDiff — what a refinement changed (deterministic, code-derived)
// ============================================================================

/// The structured "what changed" between a template and its refined successor. Computed by
/// `TemplateRefiner.apply` from before/after state — never narrated by the model unchecked. Drives the
/// mini-reveal: `headlines` are the celebration slides (upgrades announced, never asked), `contested`
/// keys become "still your thing?" cards, and `summaryLine` closes the story.
/// `Codable` so a finished refinement can persist its diff alongside the built template
/// (`StyleJobStore.saveBuilt`) — a relaunch mid-review restores the mini-reveal without re-consolidating.
struct TemplateDiff: Equatable, Codable {
    struct Upgrade: Equatable, Codable { let quote: String; let total: Int }

    var newVideoCount = 0
    var upgrades: [Upgrade] = []          // evidence rose to ALL sources → celebrated
    var newSignatures: [String] = []      // lines first seen in the new videos → asked (unconfirmed cards)
    var newHabits: [String] = []          // habit rows appended by the refinement
    var contested: [String] = []          // normalized keys: was confirmed/core, absent from the new
                                          // consolidation → re-asked, never auto-removed
    var numericShifts: [String] = []      // "avg cut 1.8s → 2.6s" when the move is > 20%

    var headlines: [String] {
        var out = upgrades.map { "“\($0.quote)” — \($0.total) for \($0.total). It's official." }
        out += newSignatures.prefix(2).map { "New one spotted: “\($0)”." }
        return out
    }

    var summaryLine: String {
        var parts: [String] = []
        if !upgrades.isEmpty { parts.append("\(upgrades.count) signature\(upgrades.count == 1 ? "" : "s") locked in") }
        let fresh = newSignatures.count + newHabits.count
        if fresh > 0 { parts.append("\(fresh) new one\(fresh == 1 ? "" : "s") spotted") }
        if !contested.isEmpty { parts.append("\(contested.count) to double-check") }
        return parts.isEmpty ? "Your style held steady — nothing changed." : parts.joined(separator: ", ") + "."
    }

    var isEmpty: Bool { upgrades.isEmpty && newSignatures.isEmpty && newHabits.isEmpty && contested.isEmpty && numericShifts.isEmpty }
}

// ============================================================================
// MARK: - TemplateRefiner — merge a re-consolidation back into a template
// ============================================================================

/// Implements the plan's ownership table verbatim: **user-edited surfaces are never clobbered**.
/// Machine-owned (profile numerics/categoricals, verbal style, sources, reveal script) adopt the new
/// consolidation; user-owned (name once renamed, summary once edited, notes, b-roll heaviness, habit
/// rows, confirmations, suppressions) survive by matched key. Nothing confirmed is ever silently
/// removed — a confirmed item the new consolidation dropped is KEPT and marked contested (asked again).
enum TemplateRefiner {

    static func apply(base: StyleTemplate, consolidated: StyleProfileRaw,
                      newSources: [StyleProfileRaw]) -> (template: StyleTemplate, diff: TemplateDiff) {
        var diff = TemplateDiff(newVideoCount: newSources.count)
        let baseSources = base.sources.isEmpty ? [base.profile] : base.sources
        let totalN = baseSources.count + newSources.count
        let suppressed = base.suppressed.map(norm).filter { !$0.isEmpty }

        func isSuppressed(_ key: String) -> Bool { suppressed.contains { key.contains($0) || $0.contains(key) } }

        // ---- machine core: adopt the consolidation, then graft user-owned data back in --------------
        var profile = consolidated
        profile.broll.heaviness = base.profile.broll.heaviness   // user-owned dial — never recomputed

        // Recurring lines — preserve confirmations + user-edited text by key; upgrades; contested.
        let baseLines = base.profile.verbalStyle.recurringLines
        var outLines: [RecurringLine] = []
        var seenKeys = Set<String>()
        for var line in profile.verbalStyle.recurringLines {
            let key = line.key
            guard !key.isEmpty, !isSuppressed(key), !seenKeys.contains(key) else { continue }
            if let b = baseLines.first(where: { $0.key == key || norm($0.quote) == norm(line.quote) }) {
                if b.confirmation == "out" { continue }        // a rejection is forever (until restored)
                line.confirmation = b.confirmation
                if !b.quote.isEmpty { line.quote = b.quote }   // user-owned wording wins
                if b.pattern?.isEmpty == false { line.pattern = b.pattern }
                if line.evidenceCount >= totalN && totalN > baseSources.count && b.evidenceCount < totalN {
                    diff.upgrades.append(.init(quote: line.quote, total: totalN))
                }
            } else {
                diff.newSignatures.append(line.quote)
            }
            seenKeys.insert(key)
            outLines.append(line)
        }
        // Contested lines: base-strong lines the consolidation dropped — kept, re-asked.
        for b in baseLines where b.confirmation != "out" {
            let key = b.key
            guard !key.isEmpty, !seenKeys.contains(key), !isSuppressed(key) else { continue }
            var kept = b
            let wasStrong = b.confirmation == "every" || (base.count >= 2 && b.evidenceCount >= base.count)
            if wasStrong { kept.confirmation = nil; diff.contested.append(key) }
            outLines.append(kept)
            seenKeys.insert(key)
        }
        profile.verbalStyle.recurringLines = outLines

        // Scalars — user-confirmed values win; a confirmed one that vanished is kept + re-asked.
        let bVS = base.profile.verbalStyle
        if bVS.signoffConfirmation != nil {
            if profile.verbalStyle.signoff.trimmingCharacters(in: .whitespaces).isEmpty && !bVS.signoff.isEmpty {
                diff.contested.append("__signoff__")
                profile.verbalStyle.signoffConfirmation = nil
            } else {
                profile.verbalStyle.signoffConfirmation = bVS.signoffConfirmation
            }
            profile.verbalStyle.signoff = bVS.signoff
        }
        if bVS.ratingConfirmation != nil {
            if profile.verbalStyle.ratingFormat.trimmingCharacters(in: .whitespaces).isEmpty && !bVS.ratingFormat.isEmpty {
                diff.contested.append("__rating__")
                profile.verbalStyle.ratingConfirmation = nil
            } else {
                profile.verbalStyle.ratingConfirmation = bVS.ratingConfirmation
            }
            profile.verbalStyle.ratingFormat = bVS.ratingFormat
            if !bVS.ratingScope.isEmpty { profile.verbalStyle.ratingScope = bVS.ratingScope }
        }

        // Section beats — matched by normalized label: keep user label + confirmation, core may only
        // STRENGTHEN silently (weakening goes through contested); unmatched base beats survive.
        var outSections = profile.structure.sections
        for si in outSections.indices {
            let secName = norm(outSections[si].section)
            guard let baseSec = base.profile.structure.sections.first(where: { norm($0.section) == secName }) else { continue }
            var matched = Set<UUID>()
            for bi in outSections[si].beats.indices {
                let key = norm(outSections[si].beats[bi].label)
                guard let bBeat = baseSec.beats.first(where: { norm($0.label) == key }) else { continue }
                matched.insert(bBeat.id)
                outSections[si].beats[bi].label = bBeat.label
                outSections[si].beats[bi].confirmation = bBeat.confirmation
                outSections[si].beats[bi].core = outSections[si].beats[bi].core || bBeat.core
                if outSections[si].beats[bi].example.isEmpty { outSections[si].beats[bi].example = bBeat.example }
            }
            for bBeat in baseSec.beats where !matched.contains(bBeat.id) {
                let key = norm(bBeat.label)
                guard !key.isEmpty, !isSuppressed(key) else { continue }
                var kept = bBeat
                if bBeat.core { kept.confirmation = nil; diff.contested.append(key) }
                outSections[si].beats.append(kept)
            }
        }
        profile.structure.sections = outSections

        // Numeric drift worth telling the creator about (> 20%).
        func shift(_ label: String, _ old: Double, _ new: Double) {
            guard old > 0, new > 0, abs(new - old) / old > 0.2 else { return }
            diff.numericShifts.append("\(label) \(String(format: "%.1f", old))s → \(String(format: "%.1f", new))s")
        }
        shift("avg cut", base.profile.pacing.averageClipLengthSeconds, profile.pacing.averageClipLengthSeconds)
        shift("typical length", base.profile.pacing.totalLengthSeconds, profile.pacing.totalLengthSeconds)

        // ---- template shell — the user-owned surfaces -----------------------------------------------
        var result = base                        // same id / createdAt / tones → activeId, poster, and
        result.profile = profile                 // library position all stay stable
        result.sources = baseSources + newSources
        result.count = result.sources.count
        result.suppressed = base.suppressed
        result.notes = base.notes

        // Summary: adopt the new brief ONLY if the current one is still untouched machine text.
        if norm(base.summary) == norm(base.machineSummary ?? "") {
            result.profile.styleBrief = consolidated.styleBrief
        } else {
            result.profile.styleBrief = base.summary
        }
        result.machineSummary = consolidated.styleBrief

        // Name: re-derive ONLY if still machine-named.
        if base.name == StyleTemplate.deriveName(base.profile) {
            result.name = StyleTemplate.deriveName(profile)
        }

        // Habits: existing rows keep label/detail/on/kind (user-owned) and gain fresh evidence; new
        // candidates append unless suppressed; nothing is auto-removed.
        var habits = base.habits
        for cand in profile.habitCandidates {
            let key = norm(cand.label)
            guard !key.isEmpty else { continue }
            if let i = habits.firstIndex(where: { norm($0.label) == key }) {
                habits[i].evidenceCount = cand.evidenceCount
            } else if !isSuppressed(key) {
                habits.append(StyleHabit(label: cand.label, detail: cand.detail.isEmpty ? nil : cand.detail,
                                         on: HabitKind.isAppliable(cand.kind),
                                         evidenceCount: cand.evidenceCount, kind: cand.kind))
                diff.newHabits.append(cand.label)
            }
        }
        result.habits = habits

        return (result, diff)
    }

    static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
