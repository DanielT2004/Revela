import SwiftUI
import UIKit

/// The post-analysis results reveal — "The First Cut · Retention Map". Replaces the old flat segment list
/// at route `.segments`. Read-only: it shows the creator the first cut Vela made and WHY it's built to
/// hold attention, in the beloved BriefView design language rendered as OUTPUT. The hero is an annotated
/// proportional filmstrip of the real assembled cut (scroll-stop flag → b-roll ticks → payoff star), so
/// the creator SEES the viral anatomy on their own food before reading a word. Everything below is honest
/// evidence: bands not fake metrics, every claim tied to a real field (see `RetentionRead`).
struct FirstCutView: View {
    @Environment(AppRouter.self) private var router
    @Environment(VideoSession.self) private var session
    @Environment(TemplateService.self) private var templates

    @State private var thumbs: [Int: UIImage] = [:]
    @State private var preview: SlicePreview?
    @State private var setAsideOpen = false
    @State private var appeared = false
    @State private var showCurtain = false

    private var store: EditPlanStore? { session.store }
    private var proxyURL: URL? { session.merged?.url }

    /// A [start,end] proxy slice to preview (from a filmstrip tile or a hook/cut card).
    private struct SlicePreview: Identifiable {
        let id = UUID()
        let start: Double
        let end: Double
        let caption: String
    }

    var body: some View {
        ZStack {
            Color.veCream.ignoresSafeArea()
            if let store, let read = read(store) {
                content(store: store, read: read)
            } else {
                ProgressView().tint(Color.veTerracotta)
            }
        }
        .overlay {
            if showCurtain {
                RevealCurtain(
                    onRevealStart: {
                        // Curtain begins lifting: play the map's entrance underneath + the "ready" haptic.
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
                    },
                    onRevealEnd: { showCurtain = false }   // curtain fully gone → remove it
                )
                .transition(.identity)   // the curtain animates its own slide-off; don't double-animate
                .zIndex(10)
            }
        }
        .task { await loadThumbnails() }
        .onAppear {
            // Show the celebratory curtain exactly once, only on a fresh reveal (never on Back-from-editor).
            let reveal = session.pendingReveal
            session.pendingReveal = false
            if reveal {
                showCurtain = true       // entrance + haptic deferred to the curtain's onReveal (at lift)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
            }
        }
        .sheet(item: $preview) { p in
            if let url = proxyURL {
                SlicePlayerSheet(url: url, start: p.start, end: p.end, caption: p.caption)
            }
        }
    }

    private func read(_ store: EditPlanStore) -> RetentionRead? {
        guard !store.order.isEmpty || !store.plan.segments.isEmpty else { return nil }
        return RetentionRead(plan: store.plan, store: store)
    }

    // MARK: - Content

    private func content(store: EditPlanStore, read: RetentionRead) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(store: store, read: read)
                    mapCard(store: store, read: read).padding(.top, 18)
                    darkSummaryCard(read: read).padding(.top, 16)
                    viralReadSection(read: read)
                    hookSection(store: store)
                    arcSection(read: read)
                    tunedSection(read: read)
                    if !store.cutTray.isEmpty { setAsideSection(store: store) }
                    styleSection(store: store)
                }
                .padding(.horizontal, 22)
                .padding(.top, 52)
                .padding(.bottom, 26)
            }
            stickyBar(store: store, read: read)
        }
    }

    // MARK: - Header

    private func header(store: EditPlanStore, read: RetentionRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BackChevronButton { router.back() }
                Spacer()
                HomeButton { router.home() }
            }
            .padding(.bottom, 16)

            Text("YOUR FIRST CUT")
                .font(VeFont.sans(11.5, weight: .heavy)).tracking(1.2)
                .foregroundStyle(Color.veTerracotta)
            Text("Here's the shape\nof your cut.")
                .font(VeFont.serif(29))
                .foregroundStyle(Color.veCharcoal)
                .padding(.top, 6)
            if !store.plan.videoSummary.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(store.plan.videoSummary)
                    .font(VeFont.serif(15.5, italic: true))
                    .foregroundStyle(Color.veNoteText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            VibeMeterPill(text: read.recapLine)
                .padding(.top, 12)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    // MARK: - The Retention Map (hero)

    private func mapCard(store: EditPlanStore, read: RetentionRead) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text("THE RETENTION MAP")
                    .font(VeFont.sans(11.5, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(Color.veTerracotta)
                Rectangle().fill(Color.veTerracotta.opacity(0.22)).frame(height: 1)
                Text("\(store.order.count)")
                    .font(VeFont.sans(11, weight: .bold)).foregroundStyle(Color.veWarmGray)
            }

            RetentionMapStrip(store: store, thumbs: thumbs, read: read, appeared: appeared) { clip in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let seg = store.segment(clip.sourceSegmentId)
                preview = SlicePreview(start: clip.inPoint, end: clip.outPoint,
                                       caption: seg?.description ?? "")
            }

            // Legend
            HStack(spacing: 14) {
                legendItem(color: Color.veTerracotta, symbol: "flag.fill", text: "scroll-stop")
                legendItem(color: Color(hex: 0x9A7350), symbol: "rectangle.fill", text: "b-roll")
                legendItem(color: Color(hex: 0xE8B65E), symbol: "star.fill", text: "payoff")
                Spacer()
            }

            Text(read.shapeLine)
                .font(VeFont.serif(14.5, italic: true))
                .foregroundStyle(Color.veNoteText)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(store.order.count) clips · b-roll \(read.brollLabel) · tap any to preview")
                .font(VeFont.sans(11.5))
                .foregroundStyle(Color.veWarmGray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.06), radius: 10, y: 3)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private func legendItem(color: Color, symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
            Text(text).font(VeFont.sans(10.5, weight: .semibold)).foregroundStyle(Color.veFaintGray)
        }
    }

    // MARK: - Dark summary card

    private func darkSummaryCard(read: RetentionRead) -> some View {
        let dark = Color(hex: 0x1C1A18)
        let ochre = Color(hex: 0xE8B65E)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(read.lengthTitle)
                    .font(VeFont.serif(30)).foregroundStyle(Color.veCream)
                if !read.targetTitle.isEmpty {
                    Text(read.targetTitle)
                        .font(VeFont.sans(12.5, weight: .semibold)).foregroundStyle(ochre)
                }
                Spacer()
                Text(read.onTarget ? "on target" : "our target")
                    .font(VeFont.sans(11, weight: .bold))
                    .foregroundStyle(ochre)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .overlay(Capsule().stroke(ochre.opacity(0.5), lineWidth: 1))
            }
            lengthBar(read: read, ochre: ochre)
            HStack(spacing: 8) {
                darkStat("KEPT", "\(read.keptCount)", ochre)
                darkStat("B-ROLL", read.brollLabel.capitalized, ochre)
                darkStat("SET ASIDE", "\(read.setAsideCount)", ochre)
            }
            Text("Long enough to land the story, short enough that people finish — finishing is what the feed rewards.")
                .font(VeFont.sans(12)).foregroundStyle(Color.veCream.opacity(0.82)).lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private func lengthBar(read: RetentionRead, ochre: Color) -> some View {
        let span = max(read.totalDuration, read.targetDuration, 1)
        let fill = max(0.02, read.totalDuration / span)
        let target = read.targetDuration > 0 ? read.targetDuration / span : nil
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.veCream.opacity(0.14)).frame(height: 6)
                Capsule().fill(ochre).frame(width: geo.size.width * fill, height: 6)
                if let target {
                    Rectangle().fill(Color.veCream.opacity(0.55))
                        .frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * target - 0.75)
                }
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }

    private func darkStat(_ label: String, _ value: String, _ ochre: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(VeFont.serif(19)).foregroundStyle(Color.veCream)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(VeFont.sans(9.5, weight: .bold)).tracking(0.5).foregroundStyle(ochre.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - The Viral Read (four-lever evidence, beneath the picture)

    private func viralReadSection(read: RetentionRead) -> some View {
        section("The viral read") {
            VStack(alignment: .leading, spacing: 10) {
                Text("our read of your footage — not a prediction")
                    .font(VeFont.serif(13, italic: true)).foregroundStyle(Color.veNoteText)
                HStack(spacing: 10) {
                    ReadCell(icon: "bolt.fill", label: "SCROLL-STOP", band: read.scrollStop.shortLabel,
                             line: read.hookWhy, tint: Color.veTerracotta)
                    ReadCell(icon: "waveform", label: "PACE", band: read.pace.word,
                             line: read.pace.line, tint: Color.veTerracotta)
                }
                HStack(spacing: 10) {
                    ReadCell(icon: "timer", label: "LENGTH", band: read.lengthTitle,
                             line: read.length.line, tint: Color.veSage)
                    ReadCell(icon: "checkmark.seal.fill", label: "PAYOFF", band: read.payoff.chip,
                             line: read.payoff.line, tint: Color(hex: 0x9A7350))
                }
            }
        }
    }

    // MARK: - The Hook (crowned scroll-stopper)

    private func hookSection(store: EditPlanStore) -> some View {
        let candidates = Array(
            store.plan.segments
                .sorted { ($0.hookScore, $1.startSeconds) > ($1.hookScore, $0.startSeconds) }
                .prefix(3)
        )
        let winner = store.hookId.flatMap { store.segment($0) } ?? candidates.first
        return section("The hook") {
            VStack(alignment: .leading, spacing: 10) {
                if let winner {
                    hookWinnerCard(winner, store: store)
                    let runners = candidates.filter { $0.id != winner.id }.prefix(2)
                    if !runners.isEmpty {
                        Text("ALSO CONSIDERED")
                            .font(VeFont.sans(10.5, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Color.veFaintGray)
                            .padding(.top, 2)
                        ForEach(Array(runners)) { seg in runnerRow(seg) }
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        router.go(.hook)
                    } label: {
                        Text("Change the hook →")
                            .font(VeFont.sans(13, weight: .bold))
                            .foregroundStyle(Color.veTerracotta)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func hookWinnerCard(_ seg: Segment, store: EditPlanStore) -> some View {
        let band = RetentionRead(plan: store.plan, store: store).scrollStop.label
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                thumbView(for: seg, height: 168, corners: .top)
                HStack(spacing: 6) {
                    RankBadge(rank: 1)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 10, weight: .bold))
                        Text("CHOSEN OPENER").font(VeFont.sans(10, weight: .bold)).tracking(0.5)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.veTerracotta, in: Capsule())
                }
                .padding(12)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    SceneChip(text: seg.sceneType.label)
                    Spacer()
                    HookScoreMeter(score: seg.hookScore)
                }
                Text(band)
                    .font(VeFont.sans(13, weight: .bold)).foregroundStyle(Color.veTerracotta)
                let why = store.plan.recommendedHook.trimmingCharacters(in: .whitespaces)
                if !why.isEmpty {
                    ReasonNote(text: why)
                } else if !seg.description.isEmpty {
                    Text(seg.description)
                        .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.veTerracotta, lineWidth: 2))
        .shadow(color: Color.veTerracotta.opacity(0.24), radius: 16, y: 8)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            preview = SlicePreview(start: seg.startSeconds,
                                   end: seg.trimToSeconds ?? seg.endSeconds,
                                   caption: seg.description)
        }
    }

    private func runnerRow(_ seg: Segment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            thumbView(for: seg, height: 62, width: 46, corners: .all)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    SceneChip(text: seg.sceneType.label)
                    Spacer()
                    HookScoreMeter(score: seg.hookScore, showLabel: false)
                }
                Text(runnerWhy(seg))
                    .font(VeFont.sans(12)).foregroundStyle(Color.veFaintGray)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 5, y: 2)
        .opacity(0.72)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            preview = SlicePreview(start: seg.startSeconds,
                                   end: seg.trimToSeconds ?? seg.endSeconds,
                                   caption: seg.description)
        }
    }

    private func runnerWhy(_ seg: Segment) -> String {
        if seg.hookScore >= 8 { return "a close call — also a strong opener" }
        if seg.hookScore >= 5 { return "a solid alternative opener" }
        return "a quieter open — lands later"
    }

    // MARK: - The Arc

    private func arcSection(read: RetentionRead) -> some View {
        section("The arc") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    arcBlock("INTRO", read.introKept, missing: read.missingSections.contains(.intro))
                    arcConnector
                    arcBlock("MIDDLE", read.middleKept, missing: read.missingSections.contains(.middle))
                    arcConnector
                    arcBlock("END", read.endKept, missing: read.missingSections.contains(.end))
                }
                if read.missingSections.isEmpty {
                    Text("A real spine — a setup, the tasting, and a verdict to close. Each stretch does a job.")
                        .font(VeFont.serif(14, italic: true)).foregroundStyle(Color.veNoteText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ReasonNote(text: missingCopy(read.missingSections))
                }
            }
        }
    }

    private func arcBlock(_ label: String, _ count: Int, missing: Bool) -> some View {
        VStack(spacing: 4) {
            Text("\(count)").font(VeFont.serif(20))
                .foregroundStyle(missing ? Color(hex: 0x9A7350) : Color.veCharcoal)
            Text(label).font(VeFont.sans(10, weight: .bold)).tracking(0.5)
                .foregroundStyle(Color.veWarmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.veSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(missing ? Color(hex: 0x9A7350).opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }

    private var arcConnector: some View {
        Rectangle().fill(Color.veTerracotta.opacity(0.4)).frame(width: 10, height: 1.5)
    }

    private func missingCopy(_ missing: [VideoSection]) -> String {
        let names = missing.map { $0.label.lowercased() }.joined(separator: " & ")
        return "No \(names) kept — worth checking you didn't lose that beat."
    }

    // MARK: - How we tuned it

    private func tunedSection(read: RetentionRead) -> some View {
        section("How we tuned it") {
            VStack(spacing: 0) {
                if read.secondsTrimmed > 0 {
                    tuneRow("scissors", "Trimmed slow lead-ins", "every second earns its place",
                            "−\(read.secondsTrimmed)s")
                    tuneDivider
                }
                tuneRow("waveform.path", "Pacing", "shots turn over to reset attention",
                        read.pace.word)
                tuneDivider
                if read.broll != .none {
                    tuneRow("rectangle.on.rectangle", "B-roll over the talk", "the eye never stalls on a face",
                            read.brollLabel.capitalized)
                    tuneDivider
                }
                tuneRow("crop", "Reframed to 9:16", "food fills the phone", "All")
            }
            .padding(4)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.veCharcoal.opacity(0.05), radius: 6, y: 2)
        }
    }

    private func tuneRow(_ icon: String, _ title: String, _ subtitle: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.veTerracotta)
                .frame(width: 34, height: 34)
                .background(Color.veSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(VeFont.sans(13.5, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                Text(subtitle).font(VeFont.sans(11.5)).foregroundStyle(Color.veWarmGray)
            }
            Spacer()
            Text(value).font(VeFont.sans(14, weight: .bold)).foregroundStyle(Color.veTerracotta)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }

    private var tuneDivider: some View {
        Rectangle().fill(Color.veCharcoal.opacity(0.06)).frame(height: 1).padding(.horizontal, 10)
    }

    // MARK: - What we set aside

    private func setAsideSection(store: EditPlanStore) -> some View {
        section("What we set aside") {
            VStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { setAsideOpen.toggle() }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(store.cutTray.count) moment\(store.cutTray.count == 1 ? "" : "s") set aside")
                                .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                            Text("Nothing deleted — restore any in the editor.")
                                .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.veWarmGray)
                            .rotationEffect(.degrees(setAsideOpen ? 180 : 0))
                    }
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: Color.veCharcoal.opacity(0.05), radius: 5, y: 2)
                }
                .buttonStyle(.plain)

                if setAsideOpen {
                    ForEach(store.cutTray, id: \.self) { id in
                        if let seg = store.segment(id) { cutCard(seg) }
                    }
                }
            }
        }
    }

    private func cutCard(_ seg: Segment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            thumbView(for: seg, height: 60, width: 44, corners: .all).opacity(0.7)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    SceneChip(text: seg.sceneType.label)
                    if seg.isLowConfidence {
                        Text("⚠ review")
                            .font(VeFont.sans(10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x9A7350))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(hex: 0x9A7350).opacity(0.12), in: Capsule())
                    }
                }
                if !seg.description.isEmpty {
                    Text(seg.description)
                        .font(VeFont.sans(12.5)).foregroundStyle(Color.veCharcoal).lineLimit(1)
                }
                if !seg.editNote.isEmpty {
                    Text(seg.editNote).font(VeFont.sans(11.5)).foregroundStyle(Color.veNoteText).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            preview = SlicePreview(start: seg.startSeconds,
                                   end: seg.trimToSeconds ?? seg.endSeconds,
                                   caption: seg.description)
        }
    }

    // MARK: - Your style (conditional)

    /// The AI's style accountability note, PLUS the cut-time bridges for habits Vela can't auto-apply:
    /// supplied-footage habits (e.g. the borrowed-clip montage) point at the manual Polish path, and a
    /// written text signature says it's pre-loaded in the text tool. Template-driven, zero prompt cost —
    /// celebration in the Reveal must never end in silence at cut time.
    @ViewBuilder
    private func styleSection(store: EditPlanStore) -> some View {
        let notes = (store.plan.styleMatchNotes ?? "").trimmingCharacters(in: .whitespaces)
        let suppliedHabits = templates.active?.habits.filter {
            $0.kind == HabitKind.suppliedFootage && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
        } ?? []
        let textLine = templates.active?.profile.verbalStyle.recurringLines.first {
            $0.medium == "text-overlay" && $0.confirmation != "out" && !$0.quote.isEmpty
        }
        if !notes.isEmpty || !suppliedHabits.isEmpty || textLine != nil {
            section("Your style") {
                VStack(alignment: .leading, spacing: 10) {
                    if !notes.isEmpty { ReasonNote(text: notes) }
                    ForEach(suppliedHabits) { habit in
                        ReasonNote(text: "Your videos usually include “\(habit.label)” — Vela can't auto-build that yet. Add those clips yourself in the editor.")
                    }
                    if let line = textLine {
                        ReasonNote(text: "Your on-screen text signature (“\((line.pattern?.isEmpty == false ? line.pattern! : line.quote))”) is pre-loaded in the editor's text tool.")
                    }
                }
            }
        }
    }

    // MARK: - Sticky bar

    private func stickyBar(store: EditPlanStore, read: RetentionRead) -> some View {
        VStack(spacing: 10) {
            Text(read.recapLine + " Ready to fine-tune?")
                .font(VeFont.serif(13.5, italic: true))
                .foregroundStyle(Color.veNoteText)
                .multilineTextAlignment(.center)
            PrimaryActionButton(title: "Start editing") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                session.editorStage = .sort
                router.go(.editor)
            }
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
        .background(
            Color.veCream
                .shadow(color: Color.veCharcoal.opacity(0.06), radius: 8, y: -3)
                .ignoresSafeArea()
        )
    }

    // MARK: - Section helper (mirrors BriefView)

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(VeFont.sans(12, weight: .bold)).tracking(0.5)
                .foregroundStyle(Color.veWarmGray)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    // MARK: - Thumbnails

    private enum ThumbCorners { case top, all }

    private func thumbView(for seg: Segment, height: CGFloat, width: CGFloat? = nil,
                           corners: ThumbCorners) -> some View {
        let shape: AnyShape = corners == .top
            ? AnyShape(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 0,
                                              bottomTrailingRadius: 0, topTrailingRadius: 18, style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        return ZStack {
            if let img = thumbs[seg.id] {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                FoodTile(tone: seg.sceneType.foodTone, cornerRadius: corners == .top ? 0 : 11)
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(shape)
    }

    private func loadThumbnails() async {
        guard let store, let url = proxyURL, thumbs.isEmpty else { return }
        // Spine clips (sampled a touch into the used slice), then the top hook candidates + cut tray.
        var jobs: [(Int, Double)] = []
        for c in store.order where !jobs.contains(where: { $0.0 == c.sourceSegmentId }) {
            jobs.append((c.sourceSegmentId, c.inPoint + 0.3))
        }
        let extras = store.plan.segments
            .sorted { $0.hookScore > $1.hookScore }.prefix(3).map(\.id) + store.cutTray
        for id in extras where !jobs.contains(where: { $0.0 == id }) {
            if let s = store.segment(id) {
                jobs.append((id, s.startSeconds + min(0.4, max(0, (s.endSeconds - s.startSeconds) / 2))))
            }
        }
        // Bounded concurrency (cap 3) so the decode burst can't spike frames during the reveal. `.task`
        // runs on the MainActor, so assigning `thumbs` after each `group.next()` is main-actor-safe; the
        // child tasks only call the (off-main, cached) generator and return values.
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            let limit = 3
            var iter = jobs.makeIterator()
            var inFlight = 0
            func submitNext() {
                guard let (id, t) = iter.next() else { return }
                inFlight += 1
                group.addTask { (id, await ThumbnailService.thumbnail(for: url, at: t)) }
            }
            for _ in 0..<limit { submitNext() }
            while inFlight > 0, let (id, img) = await group.next() {
                inFlight -= 1
                if let img { thumbs[id] = img }
                submitNext()
            }
        }
    }
}

// MARK: - Read cell (one of the four viral-read levers)

private struct ReadCell: View {
    let icon: String
    let label: String
    let band: String
    let line: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                Text(label).font(VeFont.sans(10.5, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Color.veWarmGray)
            }
            Text(band).font(VeFont.sans(14.5, weight: .bold)).foregroundStyle(Color.veCharcoal)
            Text(line).font(VeFont.sans(11.5)).foregroundStyle(Color.veWarmGray)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.veCharcoal.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Retention Map strip (annotated proportional filmstrip)

/// The hero. Lays the real assembled spine as a horizontal filmstrip (tile width ∝ clip.timelineDuration),
/// with the viral arc drawn on the SAME base-second axis: a terracotta scroll-stop flag at the hook, ochre
/// b-roll ticks + lane where `brollLane` sits, and a gold payoff star at the bite/verdict beat. All marks
/// are positioned by `xForTime`, a piecewise-linear map from timeline seconds → x, so they line up with the
/// tiles even when a short clip is floored to a minimum width. Tiles are real `View` structs (no `AnyView`).
private struct RetentionMapStrip: View {
    let store: EditPlanStore
    let thumbs: [Int: UIImage]
    let read: RetentionRead
    let appeared: Bool
    let onTap: (Clip) -> Void

    private let pps: CGFloat = 22       // points per timeline-second
    private let gap: CGFloat = 3
    private let minTile: CGFloat = 26
    private let tileH: CGFloat = 96
    private let arcH: CGFloat = 22
    private let laneH: CGFloat = 8

    private struct Tile { let clip: Clip; let seg: Segment?; let tStart: Double; let tEnd: Double; let x: CGFloat; let w: CGFloat }

    private var tiles: [Tile] {
        var out: [Tile] = []
        var t = 0.0
        var x: CGFloat = 0
        for clip in store.order {
            let dur = clip.timelineDuration
            let w = max(minTile, CGFloat(dur) * pps)
            out.append(Tile(clip: clip, seg: store.segment(clip.sourceSegmentId),
                            tStart: t, tEnd: t + dur, x: x, w: w))
            x += w + gap
            t += dur
        }
        return out
    }

    private var contentWidth: CGFloat { max(1, (tiles.last.map { $0.x + $0.w }) ?? 1) }

    /// Piecewise-linear timeline-seconds → x, honoring floored tile widths.
    private func xForTime(_ tt: Double) -> CGFloat {
        guard let first = tiles.first else { return 0 }
        if tt <= first.tStart { return first.x }
        for tile in tiles where tt >= tile.tStart && tt <= tile.tEnd {
            let frac = tile.tEnd > tile.tStart ? CGFloat((tt - tile.tStart) / (tile.tEnd - tile.tStart)) : 0
            return tile.x + frac * tile.w
        }
        return contentWidth
    }

    private var payoffTile: Tile? {
        tiles.first { t in
            guard let s = t.seg else { return false }
            return s.sceneType == .biteReaction || s.section == .end
        }
    }

    private var hasBroll: Bool { !store.brollLane.isEmpty }

    var body: some View {
        let totalH = arcH + 6 + tileH + (hasBroll ? 6 + laneH : 0)
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Tiles
                ForEach(Array(tiles.enumerated()), id: \.element.clip.id) { idx, tile in
                    FilmClipTile(seg: tile.seg,
                                 timelineDuration: tile.clip.timelineDuration,
                                 speed: tile.clip.speed,
                                 thumb: tile.seg.flatMap { thumbs[$0.id] },
                                 isHook: tile.clip.sourceSegmentId == store.hookId)
                        .frame(width: tile.w, height: tileH)
                        .offset(x: tile.x, y: arcH + 6)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.92, anchor: .bottom)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(idx) * 0.03), value: appeared)
                        .onTapGesture { onTap(tile.clip) }
                }

                // Arc rail — scroll-stop flag at the hook tile
                if let hookTile = tiles.first(where: { $0.clip.sourceSegmentId == store.hookId }) ?? tiles.first {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.veTerracotta)
                        .offset(x: hookTile.x + 2, y: 0)
                        .opacity(appeared ? 1 : 0)
                }

                // b-roll ticks on the arc rail
                ForEach(Array(store.brollLane.enumerated()), id: \.element.id) { _, o in
                    Capsule().fill(Color(hex: 0x9A7350))
                        .frame(width: 3, height: 12)
                        .offset(x: xForTime((o.startOnBase + o.endOnBase) / 2) - 1.5, y: 4)
                        .opacity(appeared ? 1 : 0)
                }

                // Payoff star
                if let p = payoffTile {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xE8B65E))
                        .offset(x: min(contentWidth - 12, xForTime((p.tStart + p.tEnd) / 2) - 6), y: 0)
                        .scaleEffect(appeared ? 1 : 0.3)
                        .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(Double(tiles.count) * 0.03 + 0.1), value: appeared)
                }

                // b-roll lane beneath the strip
                if hasBroll {
                    ForEach(Array(store.brollLane.enumerated()), id: \.element.id) { _, o in
                        let x0 = xForTime(o.startOnBase)
                        let x1 = xForTime(o.endOnBase)
                        Capsule().fill(Color(hex: 0x9A7350).opacity(0.85))
                            .frame(width: max(3, x1 - x0), height: laneH)
                            .offset(x: x0, y: arcH + 6 + tileH + 6)
                            .opacity(appeared ? 1 : 0)
                    }
                }
            }
            .frame(width: contentWidth, height: totalH, alignment: .topLeading)
            .padding(.trailing, 8)
        }
        .mask(
            LinearGradient(colors: [.black, .black, .black, .black.opacity(0.35)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}

/// One clip in the filmstrip: real thumbnail (or FoodTile), a duration chip, an optional ★HOOK pennant,
/// and a speed badge when the clip isn't at 1×. A real `View` struct (never `AnyView`) so scrolling stays smooth.
private struct FilmClipTile: View {
    let seg: Segment?
    let timelineDuration: Double
    let speed: Double
    let thumb: UIImage?
    let isHook: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                FoodTile(tone: (seg?.sceneType ?? .unknown).foodTone, cornerRadius: 10)
            }
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)

            Text("\(Int(timelineDuration.rounded()))s")
                .font(VeFont.sans(9, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)

            if isHook {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 7, weight: .bold))
                    Text("HOOK").font(VeFont.sans(8, weight: .bold)).tracking(0.3)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.veTerracotta, in: Capsule())
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if abs(speed - 1) > 0.01 {
                Text(String(format: "%.1f×", speed))
                    .font(VeFont.sans(9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 0.5))
    }
}
