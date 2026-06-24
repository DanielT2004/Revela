import SwiftUI
import UIKit

/// The required per-video brief — "Before we cut · Anything special for this one?". Gated between the
/// picker and processing so the creator confirms what THIS video needs before the slow, paid analysis.
/// Pre-filled from the active `StyleTemplate`; on submit it writes an `EditBrief` to the session, which
/// `ProcessingView` turns into the prepended brief prompt block. Every field maps to a real `editPlan`
/// lever — see `EditBrief`. Design shell: the shared `briefBindings` screen in Food Editor (onboarding).dc.html.
struct BriefView: View {
    @Environment(AppRouter.self) private var router
    @Environment(VideoSession.self) private var session
    @Environment(TemplateService.self) private var templates

    @State private var brief = EditBrief()
    @State private var didLoad = false
    @State private var swapOpen = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    templateCard.padding(.top, 20)
                    footageSection.padding(.top, 22)
                    lengthSection.padding(.top, 24)
                    section("How it opens") { hookSection }
                    section("Me on camera vs. b-roll") { leanGrid }
                    section("Make sure to keep") { keepBeatsChips }
                    section("Trim the slow stuff") { trimToggle }
                    section("Anything specific?") { noteField }
                }
                .padding(.horizontal, 22)
                .padding(.top, 52)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            submitBar
        }
        .background(Color.veCream.ignoresSafeArea())
        .onAppear {
            guard !didLoad else { return }
            brief = EditBrief.prefilled(from: templates.active)
            didLoad = true
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackChevronButton { router.back() }
                .padding(.bottom, 18)
            Text("BEFORE WE CUT")
                .font(VeFont.sans(12, weight: .bold)).tracking(0.7)
                .foregroundStyle(Color.veTerracotta)
            Text("Anything special\nfor this one?")
                .font(VeFont.serif(29))
                .foregroundStyle(Color.veCharcoal)
                .padding(.top, 6)
            Text("Set the brief for this video. We've pre-filled it from your style — tune each step, then send it to edit.")
                .font(VeFont.sans(13.5))
                .foregroundStyle(Color.veWarmGray)
                .lineSpacing(2)
                .padding(.top, 7)
        }
    }

    // MARK: template card (dark)

    private var templateCard: some View {
        let dark = Color(hex: 0x1C1A18)
        let ochre = Color(hex: 0xE8B65E)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(ochre.opacity(0.16)).frame(width: 42, height: 42)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(ochre)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(templates.active == nil ? "NO SAVED STYLE YET" : "EDITING WITH TEMPLATE")
                        .font(VeFont.sans(11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(ochre)
                    Text(templates.active?.name ?? "Smart defaults")
                        .font(VeFont.sans(16.5, weight: .bold))
                        .foregroundStyle(Color.veCream)
                }
                Spacer(minLength: 6)
                if templates.templates.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { swapOpen.toggle() }
                    } label: {
                        Text(swapOpen ? "Done" : "Swap")
                            .font(VeFont.sans(13, weight: .bold))
                            .foregroundStyle(dark)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(ochre, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if swapOpen {
                VStack(spacing: 8) {
                    ForEach(templates.templates) { t in
                        templateOption(t, ochre: ochre)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func templateOption(_ t: StyleTemplate, ochre: Color) -> some View {
        let active = t.id == templates.activeId
        return Button { selectTemplate(t) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(VeFont.sans(14, weight: .bold)).foregroundStyle(Color.veCream)
                    Text("\(t.count) video\(t.count == 1 ? "" : "s") · \(t.lenLabel)")
                        .font(VeFont.sans(11.5)).foregroundStyle(Color.veCream.opacity(0.55))
                }
                Spacer(minLength: 6)
                if active {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: 0x1C1A18))
                        .frame(width: 22, height: 22).background(ochre, in: Circle())
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(active ? ochre.opacity(0.12) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(active ? ochre.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: footage

    private var footageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR FOOTAGE")
                    .font(VeFont.sans(12, weight: .bold)).tracking(0.5).foregroundStyle(Color.veWarmGray)
                Spacer()
                Text("\(session.clips.count) clip\(session.clips.count == 1 ? "" : "s")")
                    .font(VeFont.sans(12.5, weight: .semibold)).foregroundStyle(Color.veFaintGray)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.clips) { clip in
                        ZStack(alignment: .bottomLeading) {
                            if let img = clip.thumbnail {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Color.veSurface
                            }
                            LinearGradient(colors: [Color.veCharcoal.opacity(0.6), .clear],
                                           startPoint: .bottom, endPoint: .center)
                            if let d = clip.metadata?.durationText {
                                Text(d).font(VeFont.sans(9, weight: .bold)).foregroundStyle(.white)
                                    .padding(5)
                            }
                        }
                        .frame(width: 62, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: target length

    private var lengthSection: some View {
        let binding = Binding(get: { Double(brief.lengthSeconds) },
                              set: { brief.lengthSeconds = Int($0) })
        return VStack(alignment: .leading, spacing: 10) {
            Text("TARGET LENGTH")
                .font(VeFont.sans(12, weight: .bold)).tracking(0.5).foregroundStyle(Color.veWarmGray)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(brief.lengthBandLabel).font(VeFont.serif(22)).foregroundStyle(Color.veTerracotta)
                    Spacer()
                    Text(brief.lengthDisplay).font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veCharcoal)
                }
                Text(brief.lengthBandMessage)
                    .font(VeFont.sans(12.5)).foregroundStyle(Color.veWarmGray)
                    .lineSpacing(1).frame(minHeight: 34, alignment: .top).padding(.top, 4)
                Slider(value: binding, in: 10...180, step: 5).tint(Color.veTerracotta).padding(.top, 4)
                HStack {
                    lengthTag("Punchy", .punchy)
                    Spacer(); lengthTag("Standard", .standard)
                    Spacer(); lengthTag("Detailed", .detailed)
                    Spacer(); lengthTag("In-depth", .indepth)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.veCharcoal.opacity(0.05), radius: 8, y: 2)
        }
    }

    private func lengthTag(_ text: String, _ band: EditBrief.LengthBand) -> some View {
        let on = brief.lengthBand == band
        return Text(text)
            .font(VeFont.sans(10.5, weight: on ? .bold : .semibold))
            .foregroundStyle(on ? Color.veTerracotta : Color.veFaintGray)
    }

    // MARK: how it opens — ordered multi-select (back-to-back)

    private var hookSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BriefFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(HookShot.allCases, id: \.self) { shot in
                    BriefHookChip(label: shot.label, order: hookOrder(shot)) { toggleHook(shot) }
                }
            }
            Text(brief.hookSequence.isEmpty
                 ? "Leave empty to let the AI pick the strongest opener."
                 : "Plays back-to-back in this order.")
                .font(VeFont.sans(12)).foregroundStyle(Color.veFaintGray)
        }
    }

    // MARK: me on camera vs. b-roll

    private var leanGrid: some View {
        grid(BrollLean.allCases.map(\.label), columns: 3,
             selected: index(of: brief.brollLean, in: BrollLean.allCases)) { brief.brollLean = BrollLean.allCases[$0] }
    }

    // MARK: make sure to keep

    private var keepBeatsChips: some View {
        BriefFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(KeepBeat.allCases, id: \.self) { beat in
                BriefChip(label: beat.label, selected: brief.keepBeats.contains(beat), accent: Color.veSage) {
                    toggleKeep(beat)
                }
            }
        }
    }

    // MARK: trim the slow stuff

    private var trimToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trim slow intros & dead air")
                    .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                Text("Cuts weak starts and silence — never mid-sentence.")
                    .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $brief.trimSlowParts).labelsHidden().tint(Color.veTerracotta)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: note

    private var noteField: some View {
        TextField("e.g. open with me saying this is the best taco in LA, and keep the part where I show the price",
                  text: $brief.note, axis: .vertical)
            .font(VeFont.sans(14))
            .foregroundStyle(Color.veCharcoal)
            .lineLimit(3...6)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.veCharcoal.opacity(0.12), lineWidth: 1.5))
    }

    // MARK: submit bar

    private var submitBar: some View {
        VStack(spacing: 10) {
            Text(confirmationSummary)
                .font(VeFont.serif(13.5, italic: true))
                .foregroundStyle(Color.veNoteText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: "Looks good — edit it") { submit() }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(
            Color.veCream
                .shadow(color: Color.veCharcoal.opacity(0.06), radius: 8, y: -3)
                .ignoresSafeArea()
        )
    }

    private var confirmationSummary: String {
        var parts = ["Editing a \(brief.lengthDisplay) video"]
        if !brief.hookSequence.isEmpty {
            let opener = brief.hookSequence.map { $0.label.lowercased() }.joined(separator: " → ")
            parts.append("opening on \(opener)")
        }
        switch brief.brollLean {
        case .onCamera:  parts.append("staying on camera")
        case .balanced:  break
        case .brollHeavy:parts.append("leaning on b-roll")
        }
        if !brief.keepBeats.isEmpty {
            let beats = KeepBeat.allCases.filter { brief.keepBeats.contains($0) }.map { $0.label.lowercased() }
            parts.append("keeping \(beats.joined(separator: " + "))")
        }
        return parts.joined(separator: ", ") + " — sound right?"
    }

    // MARK: reusable section + grid

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(VeFont.sans(12, weight: .bold)).tracking(0.5).foregroundStyle(Color.veWarmGray)
            content()
        }
        .padding(.top, 22)
    }

    private func grid(_ labels: [String], columns: Int, selected: Int, onPick: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                BriefSelectCell(label: label, selected: idx == selected) { onPick(idx) }
            }
        }
    }

    // MARK: actions

    private func hookOrder(_ shot: HookShot) -> Int? {
        brief.hookSequence.firstIndex(of: shot).map { $0 + 1 }
    }

    private func toggleHook(_ shot: HookShot) {
        if let i = brief.hookSequence.firstIndex(of: shot) {
            brief.hookSequence.remove(at: i)
        } else {
            brief.hookSequence.append(shot)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toggleKeep(_ beat: KeepBeat) {
        if brief.keepBeats.contains(beat) { brief.keepBeats.remove(beat) }
        else { brief.keepBeats.insert(beat) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func selectTemplate(_ t: StyleTemplate) {
        templates.setActive(t.id)
        // Re-seed the usual settings, but preserve what the creator already set for THIS video.
        var seeded = EditBrief.prefilled(from: t)
        seeded.keepBeats = brief.keepBeats
        seeded.trimSlowParts = brief.trimSlowParts
        seeded.note = brief.note
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            brief = seeded
            swapOpen = false
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func submit() {
        session.brief = brief
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Log.app("📝 Brief — ~\(brief.lengthSeconds)s · open \(brief.hookSequence.map(\.label)) · lean \(brief.brollLean.label) · keep \(brief.keepBeats.map(\.label)) · trim \(brief.trimSlowParts).")
        router.go(.processing)
    }

    private func index<T: Equatable>(of value: T, in all: [T]) -> Int {
        all.firstIndex(of: value) ?? 0
    }
}

// MARK: - Small building blocks (real View structs — no AnyView in this list-heavy screen)

/// One single-select option cell (terracotta border + tint + corner check when active).
private struct BriefSelectCell: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(VeFont.sans(13.5, weight: .semibold))
                .foregroundStyle(selected ? Color.veTerracotta : Color.veCharcoal)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12).padding(.horizontal, 8)
                .background(selected ? Color.veTerracotta.opacity(0.1) : Color.white,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.veTerracotta : Color.veCharcoal.opacity(0.12), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// One multi-select chip (fills with `accent` when on).
private struct BriefChip: View {
    let label: String
    let selected: Bool
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected {
                    Text("✓").font(VeFont.sans(13, weight: .heavy)).foregroundStyle(.white)
                }
                Text(label)
                    .font(VeFont.sans(13.5, weight: .semibold))
                    .foregroundStyle(selected ? .white : Color.veCharcoal)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(selected ? accent : Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Color.clear : Color.veCharcoal.opacity(0.12), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// An opener chip that shows its 1-based ORDER (back-to-back sequence) when selected, instead of a check.
private struct BriefHookChip: View {
    let label: String
    let order: Int?
    let action: () -> Void
    var body: some View {
        let on = order != nil
        return Button(action: action) {
            HStack(spacing: 6) {
                if let order {
                    Text("\(order)")
                        .font(VeFont.sans(11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Color.veTerracotta, in: Circle())
                }
                Text(label)
                    .font(VeFont.sans(13.5, weight: .semibold))
                    .foregroundStyle(on ? Color.veTerracotta : Color.veCharcoal)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(on ? Color.veTerracotta.opacity(0.1) : Color.white,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(on ? Color.veTerracotta : Color.veCharcoal.opacity(0.12), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// Minimal wrap layout for the chip rows (iOS 16+ `Layout`).
private struct BriefFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxW {
                widest = max(widest, x - spacing); x = 0; y += rowH + lineSpacing; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: maxW == .infinity ? widest : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX; y += rowH + lineSpacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
