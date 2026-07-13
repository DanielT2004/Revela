import SwiftUI
import UIKit

enum TemplateEditorMode { case onboarding, newTemplate, edit }

/// The profile/payoff screen — fully editable. Used by onboarding ("Save & enter Vela"), the create flow
/// ("Save template"), and re-opening a saved template ("Save changes"). Binds directly to a `StyleTemplate`:
/// name, summary, the **owned toggle list** (rename / remove ✕ / add), the **recipe** (add/remove/edit),
/// the **stat values** (which steer the cut), and a **free notes** field all fold straight back into the
/// profile, so what the creator changes here changes how new videos get cut (M7).
struct TemplateEditorView: View {
    @Binding var template: StyleTemplate
    var clips: [SourceClip] = []
    var mode: TemplateEditorMode = .onboarding
    let onSave: () -> Void
    var onCancel: (() -> Void)? = nil
    /// The "sharpen this style" hand-off (M6): fires with the newly-picked videos; RootView starts the
    /// refinement. Only offered in `.edit` mode while the template has fewer than 3 source videos.
    var onRefine: (([PickedClip]) -> Void)? = nil

    @State private var showRefinePicker = false
    @State private var refineDownload: Progress? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                nameField.padding(.top, 7)
                learnedLine.padding(.top, 8)

                // IA: summary → signature is the "feel understood" pair; the tuning dials (stats, b-roll)
                // come after the identity content, below the source videos.
                summaryCard.padding(.top, 18)
                SignatureLinesCard(template: $template).padding(.top, 14)

                if mode == .edit, template.count < 3, onRefine != nil {
                    sharpenCard.padding(.top, 14)
                }

                if !clips.isEmpty {
                    sectionHeader("Videos behind it", trailing: "\(template.count) clip\(template.count == 1 ? "" : "s")")
                        .padding(.top, 24).padding(.bottom, 11)
                    videoGrid
                }

                statRow.padding(.top, 18)
                brollCard.padding(.top, 9)

                Text("Habits we'll keep")
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veCharcoal)
                    .padding(.top, 26)
                Text("The habits we learned from your videos — toggle, rename, remove, or add your own. Anything on is sent to the AI when it cuts.")
                    .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                    .padding(.top, 4).padding(.bottom, 13)
                habitList

                recipeCard.padding(.top, 26)
                notesCard.padding(.top, 14)

                saveButton.padding(.top, 22)
            }
            .padding(.horizontal, 22).padding(.top, 64).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.veCream.ignoresSafeArea())
        .fullScreenCover(isPresented: $showRefinePicker) {
            VideoPicker(preselectedIdentifiers: [], selectionLimit: max(1, 3 - template.count),
                        onLoadingBegan: { progress in
                            showRefinePicker = false
                            refineDownload = progress
                        }) { picked, _ in
                showRefinePicker = false
                refineDownload = nil
                guard !picked.isEmpty else { return }
                onRefine?(picked)
            }
            .ignoresSafeArea()
        }
        .overlay { if let p = refineDownload { MediaDownloadOverlay(progress: p) } }
    }

    // MARK: sharpen (refinement CTA — M6)

    /// "Add 1–2 more videos" — cross-video repetition is what upgrades a guess to a confirmed signature.
    /// The subcopy sets the cost up front (another analysis wait) AND the payoff ("what held up").
    private var sharpenCard: some View {
        Button {
            showRefinePicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.veTerracotta)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sharpen this style")
                        .font(VeFont.sans(14.5, weight: .bold)).foregroundStyle(Color.veCharcoal)
                    Text("Add \(3 - template.count == 1 ? "1 more video" : "1–2 more videos") to confirm your signature.")
                        .font(VeFont.sans(12.5)).foregroundStyle(Color.veNoteText)
                    Text("Takes a few minutes per video — I'll tell you what held up.")
                        .font(VeFont.sans(11.5)).foregroundStyle(Color.veWarmGray)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.veWarmGray)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.veTerracotta.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.veTerracotta.opacity(0.35), style: StrokeStyle(lineWidth: 1.3, dash: [6, 4])))
        }
        .buttonStyle(.plain)
    }

    // MARK: header

    private var eyebrowText: String {
        switch mode {
        case .onboarding:  return "YOUR STYLE TEMPLATE"
        case .newTemplate: return "NEW TEMPLATE — REVIEW & SAVE"
        case .edit:        return "EDIT STYLE TEMPLATE"
        }
    }

    private var topRow: some View {
        HStack {
            Text(eyebrowText)
                .font(VeFont.sans(11, weight: .bold)).tracking(1.4).foregroundStyle(Color.veTerracotta)
            Spacer()
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(VeFont.sans(13, weight: .semibold)).foregroundStyle(Color.veWarmGray)
            }
        }
    }

    private var nameField: some View {
        TextField("Name this style", text: $template.name, axis: .vertical)
            .font(VeFont.serif(31)).foregroundStyle(Color.veCharcoal)
            .lineLimit(1...2)
    }

    /// Evidence framing over a confidence theater number: one video = honest "add more to confirm"
    /// (doubles as the refinement CTA setup); N≥2 earns the confidence figure.
    private var learnedLine: some View {
        Group {
            if template.count <= 1 {
                Text("Learned from 1 video · ")
                    .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                + Text("add more to confirm your signature")
                    .font(VeFont.sans(13, weight: .semibold)).foregroundStyle(Color(hex: 0x9A7350))
            } else {
                Text("Learned from \(template.count) videos · ")
                    .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                + Text("\(template.confidence)% confident")
                    .font(VeFont.sans(13, weight: .bold)).foregroundStyle(Color.veSage)
            }
        }
    }

    // MARK: summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT WE HEARD IN YOUR EDITS")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.0).foregroundStyle(Color.veTerracotta)
            TextField("Describe the style…", text: $template.summary, axis: .vertical)
                .font(VeFont.serif(18, italic: true)).foregroundStyle(Color(hex: 0x4A443C))
                .lineSpacing(3)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0xEAE2D4), lineWidth: 1))
    }

    // MARK: stats (editable — these steer the cut)

    private var statRow: some View {
        let hook = Binding(get: { template.profile.hook.resolved },
                           set: { template.profile.hook.type = $0; template.profile.hook.typeCustom = nil })
        return HStack(spacing: 9) {
            numberStat($template.profile.pacing.averageClipLengthSeconds, suffix: "s", label: "avg cut\nlength")
            numberStat($template.profile.pacing.totalLengthSeconds, suffix: "s", label: "typical\nlength")
            textStat(hook, label: "hook\nstyle")
        }
    }

    private func numberStat(_ value: Binding<Double>, suffix: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 1) {
                // Cap the DISPLAY at one decimal (2.8s, not 2.833333s) — the stored Double keeps full
                // precision and typing is unaffected; the field just re-renders rounded on commit.
                TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).fixedSize()
                    .font(VeFont.serif(20)).foregroundStyle(Color.veCharcoal)
                Text(suffix).font(VeFont.serif(15)).foregroundStyle(Color.veWarmGray)
            }
            Text(label).font(VeFont.sans(11)).foregroundStyle(Color.veWarmGray).lineSpacing(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    // MARK: B-roll heaviness — how much of the final video auto-fills with b-roll over the talking

    private var brollCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("B-roll heaviness")
                    .font(VeFont.sans(13, weight: .bold)).foregroundStyle(Color.veCharcoal)
                Spacer()
                Text("\(Int((min(1, max(0, template.profile.broll.heaviness)) * 100).rounded()))%")
                    .font(VeFont.serif(20)).foregroundStyle(Color.veTerracotta)
            }
            Slider(value: $template.profile.broll.heaviness, in: 0...0.5)
                .tint(Color.veTerracotta)
            HStack {
                Text("Light").font(VeFont.sans(10.5)).foregroundStyle(Color.veWarmGray)
                Spacer()
                Text("Heavy").font(VeFont.sans(10.5)).foregroundStyle(Color.veWarmGray)
            }
            Text("How much of the video auto-covers with b-roll over your talking.")
                .font(VeFont.sans(11)).foregroundStyle(Color.veWarmGray)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    private func textStat(_ value: Binding<String>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Long custom hook values wrap to a second line instead of vanishing into an ellipsis.
            TextField("hook", text: value, axis: .vertical)
                .font(VeFont.serif(16)).foregroundStyle(Color.veCharcoal)
                .lineLimit(1...2).minimumScaleFactor(0.75)
            Text(label).font(VeFont.sans(11)).foregroundStyle(Color.veWarmGray).lineSpacing(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    // MARK: videos grid (only when we have the source clips, i.e. fresh analysis)

    private var videoGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)
        let n = max(clips.count, min(8, max(4, template.count)))
        return LazyVGrid(columns: cols, spacing: 7) {
            ForEach(0..<n, id: \.self) { i in
                // The CONTAINER owns the geometry (cell width → 9:13 height); the thumbnail lives in an
                // overlay so its intrinsic size can never inflate the tile (a bare `.aspectRatio(.fill)`
                // around a `.scaledToFill()` image let the image's pixel size drive layout — tiles blew
                // past their grid slot and overlapped the section header).
                Color.clear
                    .aspectRatio(9.0/13.0, contentMode: .fit)
                    .overlay {
                        if i < clips.count, let thumb = clips[i].thumbnail {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            FoodTile(tone: FoodTone.tone(for: template.tones.isEmpty ? i : template.tones[i % template.tones.count]), cornerRadius: 9)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    // MARK: habits (owned list)

    @State private var showAllComingSoon = false

    /// Live toggles first; coming-soon habits (supplied-footage / visual-effect) grouped under a quiet
    /// sub-header at the bottom, capped at 2 visible — the appliable identity must visually outweigh the
    /// not-yet. "Make it a live habit" is the user rescue for a misclassified kind.
    private var habitList: some View {
        let comingSoonIds = template.habits.filter { !$0.isAppliable }.map(\.id)
        let visibleComingSoon = showAllComingSoon ? Set(comingSoonIds) : Set(comingSoonIds.prefix(2))
        return VStack(spacing: 11) {
            ForEach($template.habits) { $habit in
                if habit.isAppliable {
                    HabitRow(habit: $habit, sourceCount: template.count, onRemove: { removeHabit(habit.id) })
                }
            }
            addButton(title: "Add option") {
                template.habits.append(StyleHabit(label: "", on: true))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            if !comingSoonIds.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("SPOTTED — ON THE ROADMAP")
                        .font(VeFont.sans(10, weight: .bold)).tracking(1.0).foregroundStyle(Color(hex: 0x9A7350))
                    Spacer()
                }
                .padding(.top, 8)
                Text("Vela can't apply these edits yet — they're how we know your style.")
                    .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach($template.habits) { $habit in
                    if !habit.isAppliable && visibleComingSoon.contains(habit.id) {
                        ComingSoonHabitRow(habit: $habit,
                                           onMakeLive: { makeLive(habit.id) },
                                           onRemove: { removeHabit(habit.id) })
                    }
                }
                if comingSoonIds.count > 2 && !showAllComingSoon {
                    Button("\(comingSoonIds.count - 2) more") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showAllComingSoon = true }
                    }
                    .font(VeFont.sans(12, weight: .semibold)).foregroundStyle(Color.veWarmGray)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func removeHabit(_ id: UUID) {
        // Machine rows the user rejects are suppressed so refinement never resurrects them.
        if let habit = template.habits.first(where: { $0.id == id }) {
            let key = habit.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !template.suppressed.contains(key) { template.suppressed.append(key) }
        }
        template.habits.removeAll { $0.id == id }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func makeLive(_ id: UUID) {
        guard let i = template.habits.firstIndex(where: { $0.id == id }) else { return }
        template.habits[i].kind = HabitKind.selection
        template.habits[i].on = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: breakdown (the learned intro / middle / end structure — editable)

    private var recipeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOW WE'LL RECREATE IT")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.0).foregroundStyle(Color(hex: 0xE8B65E))
            Text("The breakdown — intro, middle, end")
                .font(VeFont.serif(19)).foregroundStyle(Color.veCream)
                .padding(.top, 5).padding(.bottom, 6)
            Text("The beats we heard in each section. Edit, remove, or add — these become the checklist before every cut.")
                .font(VeFont.sans(12)).foregroundStyle(Color.veCream.opacity(0.6))
                .padding(.bottom, 16)

            VStack(spacing: 18) {
                ForEach($template.profile.structure.sections) { $section in
                    sectionGroup($section)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.veCharcoal, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { ensureSections() }
    }

    @ViewBuilder
    private func sectionGroup(_ section: Binding<StyleSection>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sectionTitle(section.wrappedValue.section))
                    .font(VeFont.sans(12, weight: .bold)).tracking(0.6).foregroundStyle(Color(hex: 0xE8B65E))
                Text(section.wrappedValue.beats.count == 1 ? "1 beat" : "\(section.wrappedValue.beats.count) beats")
                    .font(VeFont.sans(11)).foregroundStyle(Color.veCream.opacity(0.45))
            }
            ForEach(section.beats) { $beat in
                SectionBeatRow(beat: $beat, sourceCount: template.count, onRemove: { removeBeat(beat.id, in: section) })
            }
            Button {
                section.wrappedValue.beats.append(SectionBeat(label: "", core: true))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("Add beat").font(VeFont.sans(13, weight: .bold))
                }
                .foregroundStyle(Color.veCream.opacity(0.85))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.veCream.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "intro":  return "INTRO"
        case "middle": return "MIDDLE"
        case "end":    return "END"
        default:       return raw.isEmpty ? "SECTION" : raw.uppercased()
        }
    }

    private func removeBeat(_ id: UUID, in section: Binding<StyleSection>) {
        section.wrappedValue.beats.removeAll { $0.id == id }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Ensure the editor always shows intro → middle → end (even for a legacy template with no learned
    /// sections), in that order — done on appear so we never mutate during render.
    private func ensureSections() {
        let canonical = ["intro", "middle", "end"]
        var secs = template.profile.structure.sections
        for name in canonical where !secs.contains(where: { $0.section.trimmingCharacters(in: .whitespaces).lowercased() == name }) {
            secs.append(StyleSection(section: name))
        }
        secs.sort {
            (canonical.firstIndex(of: $0.section.trimmingCharacters(in: .whitespaces).lowercased()) ?? canonical.count)
            < (canonical.firstIndex(of: $1.section.trimmingCharacters(in: .whitespaces).lowercased()) ?? canonical.count)
        }
        if secs != template.profile.structure.sections { template.profile.structure.sections = secs }
    }

    // MARK: notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTHING ELSE?")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.0).foregroundStyle(Color.veTerracotta)
            Text("Free-form instructions — also sent to the AI when it cuts.")
                .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
            TextField("e.g. never speed-ramp; always end on a wide plate shot", text: $template.notes, axis: .vertical)
                .font(VeFont.sans(14)).foregroundStyle(Color.veCharcoal).lineSpacing(2).lineLimit(1...6)
                .padding(.top, 2)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    // MARK: save

    private var saveButton: some View {
        let (title, fill, fg, icon): (String, Color, Color, String?) = {
            switch mode {
            case .onboarding:  return ("Save & enter Vela", Color.veTerracotta, Color.veOnTerracotta, nil)
            case .newTemplate: return ("Save template", Color.veSage, .white, "checkmark")
            case .edit:        return ("Save changes", Color.veTerracotta, Color.veOnTerracotta, "checkmark")
            }
        }()
        return Button(action: onSave) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(VeFont.sans(16, weight: .bold))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: fill.opacity(0.4), radius: 11, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: shared bits

    private func addButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                Text(title).font(VeFont.sans(14, weight: .bold))
            }
            .foregroundStyle(Color.veTerracotta)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Color.veTerracotta.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.veTerracotta.opacity(0.4), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veCharcoal)
            Spacer()
            Text(trailing).font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
        }
    }
}

// MARK: - Rows (real View structs, not AnyView)

private struct HabitRow: View {
    @Binding var habit: StyleHabit
    var sourceCount: Int = 1
    let onRemove: () -> Void

    private var tier: EvidenceTier {
        EvidenceTier.tier(confirmation: nil, evidence: habit.evidenceCount, sourceCount: sourceCount)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Name this habit", text: $habit.label)
                        .font(VeFont.sans(14.5, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                    if let label = tier.label {
                        Text(label)
                            .font(VeFont.sans(8.5, weight: .bold)).tracking(0.5)
                            .foregroundStyle(tier.isGold ? Color.veCharcoal : Color.veNoteText)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(tier.isGold ? Color(hex: 0xE8B65E).opacity(0.9) : Color.veSurface, in: Capsule())
                            .fixedSize()
                    }
                }
                if let detail = habit.detail, !detail.isEmpty {
                    Text(detail).font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray).lineSpacing(1)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $habit.on).labelsHidden().tint(Color.veTerracotta)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.veWarmGray)
                    .frame(width: 26, height: 26).background(Color.veSurface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }
}

/// A habit Vela can't apply yet — no live toggle (a toggle that does nothing would be a lie): the habit,
/// an ochre COMING SOON chip, a remove ✕, and the "Make it a live habit" kind-rescue. Visually quieter
/// than live rows (flat veSurface, no white card shadow) so the live list stays scannable.
private struct ComingSoonHabitRow: View {
    @Binding var habit: StyleHabit
    let onMakeLive: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(habit.label)
                        .font(VeFont.sans(14.5, weight: .semibold)).foregroundStyle(Color.veCharcoal.opacity(0.75))
                    Text("COMING SOON")
                        .font(VeFont.sans(8.5, weight: .bold)).tracking(0.6).foregroundStyle(Color.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(hex: 0x9A7350).opacity(0.9), in: Capsule())
                        .fixedSize()
                }
                if let detail = habit.detail, !detail.isEmpty {
                    Text(detail).font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray).lineSpacing(1)
                }
                Button("Vela can do this? Make it a live habit", action: onMakeLive)
                    .font(VeFont.sans(11.5, weight: .semibold)).foregroundStyle(Color.veSage)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.veWarmGray)
                    .frame(width: 26, height: 26).background(Color.white.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.veSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct SectionBeatRow: View {
    @Binding var beat: SectionBeat
    var sourceCount: Int = 1
    let onRemove: () -> Void

    /// Presentation only — `core` still drives the constraint builder. Gold is EARNED (user-confirmed or
    /// all-N sources); at N=1 unconfirmed beats show no badge (the section header carries the honesty line).
    private var tier: EvidenceTier {
        EvidenceTier.tier(confirmation: beat.confirmation, evidence: beat.evidenceCount, sourceCount: sourceCount)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            TextField("0–2s", text: $beat.timeHint)
                .font(VeFont.sans(11, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color(hex: 0xE8B65E))
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name this beat", text: $beat.label, axis: .vertical)
                    .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCream).lineSpacing(2)
                if !beat.example.isEmpty {
                    Text("e.g. \(beat.example)")
                        .font(VeFont.sans(11.5)).foregroundStyle(Color.veCream.opacity(0.45)).lineSpacing(1)
                }
                if let label = tier.label {
                    Text(label)
                        .font(VeFont.sans(9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(tier.isGold ? Color.veCharcoal : Color.veCream.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tier.isGold ? Color(hex: 0xE8B65E).opacity(0.85) : Color.white.opacity(0.12), in: Capsule())
                }
            }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.veCream.opacity(0.7))
                    .frame(width: 24, height: 24).background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
