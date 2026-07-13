import SwiftUI
import UIKit

/// "YOUR SIGNATURE" — the template editor's verbal-identity card: recurring lines (spoken + on-screen
/// text), the sign-off, and the rating formula, each with a role chip + an `EvidenceTier` badge (max 2
/// chips per row; the delivery note stays plain text). Sits directly after the summary card — summary →
/// signature is the "feel understood" pair; the tuning controls come after.
///
/// Removal is RECOVERABLE, never oblivion: ✕ marks a line `confirmation == "out"` and appends its key to
/// `template.suppressed` (which drives both the prompt filter and consolidation's REJECTED LINES); the
/// row moves into a collapsed "Left out (n)" footer with a Restore affordance. Editing a quote un-
/// suppresses its key (typing a line back is the strongest possible "it's mine").
struct SignatureLinesCard: View {
    @Binding var template: StyleTemplate
    @State private var showLeftOut = false

    private var lines: Binding<[RecurringLine]> { $template.profile.verbalStyle.recurringLines }
    private var activeLines: [RecurringLine] { template.profile.verbalStyle.recurringLines.filter { $0.confirmation != "out" } }
    private var leftOutLines: [RecurringLine] { template.profile.verbalStyle.recurringLines.filter { $0.confirmation == "out" } }
    /// Scalar sign-off row only when no recurring line already carries the sign-off role (no dupes).
    private var showsScalarSignoff: Bool {
        !template.profile.verbalStyle.signoff.trimmingCharacters(in: .whitespaces).isEmpty
            && !activeLines.contains { $0.role == "sign-off" }
    }
    private var showsRating: Bool {
        !template.profile.verbalStyle.ratingFormat.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var isEmpty: Bool { activeLines.isEmpty && !showsScalarSignoff && !showsRating }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR SIGNATURE")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.0).foregroundStyle(Color.veTerracotta)

            if isEmpty {
                Text("No signature lines learned yet — add more videos, or type your catchphrase below.")
                    .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
            }

            ForEach(lines) { $line in
                if line.confirmation != "out" {
                    SignatureLineRow(line: $line, sourceCount: template.count,
                                     onEditedQuote: { unsuppress($0) },
                                     onLeaveOut: { leaveOut($line.wrappedValue) })
                }
            }

            if showsScalarSignoff { scalarSignoffRow }
            if showsRating { ratingRow }

            addLineButton
            if !leftOutLines.isEmpty { leftOutFooter }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    // MARK: scalar rows

    private var scalarSignoffRow: some View {
        let vs = $template.profile.verbalStyle
        return SignatureScalarRow(
            eyebrow: "SIGN-OFF",
            text: vs.signoff,
            tier: EvidenceTier.tier(confirmation: template.profile.verbalStyle.signoffConfirmation,
                                    evidence: template.count, sourceCount: template.count),
            onRemove: {
                suppress(template.profile.verbalStyle.signoff)
                template.profile.verbalStyle.signoff = ""
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            })
    }

    private var ratingRow: some View {
        let vs = $template.profile.verbalStyle
        let scope = template.profile.verbalStyle.ratingScope
        return SignatureScalarRow(
            eyebrow: scope == "per-item" ? "RATING · PER DISH" : "RATING",
            text: vs.ratingFormat,
            tier: EvidenceTier.tier(confirmation: template.profile.verbalStyle.ratingConfirmation,
                                    evidence: template.count, sourceCount: template.count),
            onRemove: {
                template.profile.verbalStyle.ratingFormat = ""
                template.profile.verbalStyle.ratingScope = ""
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            })
    }

    private var addLineButton: some View {
        Button {
            // User-typed lines are user-confirmed by definition — they wrote it down deliberately.
            template.profile.verbalStyle.recurringLines.append(
                RecurringLine(role: "throughout", position: "mid", confirmation: "every"))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text("Add a line").font(VeFont.sans(13, weight: .bold))
            }
            .foregroundStyle(Color.veTerracotta)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Color.veTerracotta.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.veTerracotta.opacity(0.4), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    // MARK: left-out footer (recoverable, not oblivion)

    private var leftOutFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showLeftOut.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showLeftOut ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Left out (\(leftOutLines.count))").font(VeFont.sans(12, weight: .semibold))
                }
                .foregroundStyle(Color.veWarmGray)
            }
            .buttonStyle(.plain)

            if showLeftOut {
                ForEach(leftOutLines) { line in
                    HStack(spacing: 8) {
                        Text("“\(line.quote)”")
                            .font(VeFont.serif(14, italic: true)).foregroundStyle(Color.veFaintGray)
                            .lineLimit(2).strikethrough(color: Color.veFaintGray.opacity(0.6))
                        Spacer(minLength: 0)
                        Button("Restore") { restore(line) }
                            .font(VeFont.sans(12, weight: .bold)).foregroundStyle(Color.veSage)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: suppression plumbing

    private func leaveOut(_ line: RecurringLine) {
        if let i = template.profile.verbalStyle.recurringLines.firstIndex(where: { $0.id == line.id }) {
            template.profile.verbalStyle.recurringLines[i].confirmation = "out"
        }
        suppress(line.key)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func restore(_ line: RecurringLine) {
        if let i = template.profile.verbalStyle.recurringLines.firstIndex(where: { $0.id == line.id }) {
            template.profile.verbalStyle.recurringLines[i].confirmation = nil
        }
        unsuppress(line.key)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func suppress(_ key: String) {
        let k = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !template.suppressed.contains(k) else { return }
        template.suppressed.append(k)
    }

    private func unsuppress(_ key: String) {
        let k = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        template.suppressed.removeAll { $0 == k || k.contains($0) || $0.contains(k) }
    }
}

// MARK: - Rows (real View structs per the playbook)

private struct SignatureLineRow: View {
    @Binding var line: RecurringLine
    let sourceCount: Int
    let onEditedQuote: (String) -> Void
    let onLeaveOut: () -> Void

    private var tier: EvidenceTier {
        EvidenceTier.tier(confirmation: line.confirmation, evidence: line.evidenceCount, sourceCount: sourceCount)
    }
    private var roleChip: String {
        if line.medium == "text-overlay" { return "TEXT" }
        switch line.role {
        case "hook":      return "HOOK"
        case "verdict":   return "VERDICT"
        case "sign-off":  return "SIGN-OFF"
        case "transition":return "TRANSITION"
        default:          return "LINE"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                TextField("Your line, word for word…", text: $line.quote, axis: .vertical)
                    .font(VeFont.serif(17, italic: true)).foregroundStyle(Color.veCharcoal)
                    .lineSpacing(2).lineLimit(1...3)
                    .onChange(of: line.quote) { _, new in onEditedQuote(new.lowercased()) }
                HStack(spacing: 6) {
                    chip(roleChip, gold: false)
                    if let label = tier.label { chip(label, gold: tier.isGold) }
                }
                if !line.deliveryNote.isEmpty {
                    Text(line.deliveryNote).font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                }
            }
            Spacer(minLength: 0)
            Button(action: onLeaveOut) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.veWarmGray)
                    .frame(width: 26, height: 26).background(Color.veSurface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chip(_ text: String, gold: Bool) -> some View {
        Text(text)
            .font(VeFont.sans(9, weight: .bold)).tracking(0.6)
            .foregroundStyle(gold ? Color.veCharcoal : Color.veNoteText)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(gold ? Color(hex: 0xE8B65E).opacity(0.9) : Color.veSurface, in: Capsule())
    }
}

private struct SignatureScalarRow: View {
    let eyebrow: String
    @Binding var text: String
    let tier: EvidenceTier
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(eyebrow)
                        .font(VeFont.sans(9, weight: .bold)).tracking(0.6).foregroundStyle(Color.veNoteText)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Color.veSurface, in: Capsule())
                    if let label = tier.label {
                        Text(label)
                            .font(VeFont.sans(9, weight: .bold)).tracking(0.6)
                            .foregroundStyle(tier.isGold ? Color.veCharcoal : Color.veNoteText)
                            .padding(.horizontal, 6).padding(.vertical, 2.5)
                            .background(tier.isGold ? Color(hex: 0xE8B65E).opacity(0.9) : Color.veSurface, in: Capsule())
                    }
                }
                TextField("…", text: $text, axis: .vertical)
                    .font(VeFont.serif(17, italic: true)).foregroundStyle(Color.veCharcoal)
                    .lineSpacing(2).lineLimit(1...3)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.veWarmGray)
                    .frame(width: 26, height: 26).background(Color.veSurface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
