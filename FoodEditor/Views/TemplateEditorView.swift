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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                nameField.padding(.top, 7)
                learnedLine.padding(.top, 8)

                summaryCard.padding(.top, 18)
                statRow.padding(.top, 14)
                brollCard.padding(.top, 9)

                if !clips.isEmpty {
                    sectionHeader("Videos behind it", trailing: "\(template.count) clip\(template.count == 1 ? "" : "s")")
                        .padding(.top, 24).padding(.bottom, 11)
                    videoGrid
                }

                Text("Habits we'll keep")
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veCharcoal)
                    .padding(.top, 26)
                Text("Toggle, rename, remove, or add your own — anything on is sent to the AI when it cuts.")
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

    private var learnedLine: some View {
        Text("Learned from \(template.count) video\(template.count == 1 ? "" : "s") · ")
            .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
        + Text("\(template.confidence)% confident")
            .font(VeFont.sans(13, weight: .bold)).foregroundStyle(Color.veSage)
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
                TextField("0", value: value, format: .number)
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
            TextField("hook", text: value)
                .font(VeFont.serif(16)).foregroundStyle(Color.veCharcoal).lineLimit(1).minimumScaleFactor(0.5)
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
                Group {
                    if i < clips.count, let thumb = clips[i].thumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        FoodTile(tone: FoodTone.tone(for: template.tones.isEmpty ? i : template.tones[i % template.tones.count]), cornerRadius: 9)
                    }
                }
                .aspectRatio(9.0/13.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    // MARK: habits (owned list)

    private var habitList: some View {
        VStack(spacing: 11) {
            ForEach($template.habits) { $habit in
                HabitRow(habit: $habit, onRemove: { removeHabit(habit.id) })
            }
            addButton(title: "Add option") {
                template.habits.append(StyleHabit(label: "", on: true))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func removeHabit(_ id: UUID) {
        template.habits.removeAll { $0.id == id }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
                SectionBeatRow(beat: $beat, onRemove: { removeBeat(beat.id, in: section) })
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
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name this habit", text: $habit.label)
                    .font(VeFont.sans(14.5, weight: .semibold)).foregroundStyle(Color.veCharcoal)
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

private struct SectionBeatRow: View {
    @Binding var beat: SectionBeat
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            TextField("0–2s", text: $beat.timeHint)
                .font(VeFont.sans(11, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color(hex: 0xE8B65E))
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name this beat", text: $beat.label, axis: .vertical)
                    .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCream).lineSpacing(2)
                if beat.core {
                    Text("ALWAYS")
                        .font(VeFont.sans(9, weight: .bold)).tracking(0.6).foregroundStyle(Color.veCharcoal)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: 0xE8B65E).opacity(0.85), in: Capsule())
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
