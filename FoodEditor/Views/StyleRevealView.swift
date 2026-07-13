import SwiftUI
import UIKit

/// **The Reveal** — the personalized, narrated moment right after a style learn: an editorial voice tells
/// the creator what it saw (second person, their first name, their own words quoted back), then asks them
/// to lock in each detected signature. This is the app's feel-heard beat — a story, not a form.
///
/// Three phases:
///  1. **Story** — full-bleed charcoal slides (the dark recipe-card aesthetic inverted to full screen):
///     opener → reveal_script lines → pull-quote slide(s). Auto-advance with text-length-scaled dwell,
///     tap-right to advance, tap-left to go back, hold to pause. NEW linear engine — the Analyzing
///     screen's looping narration timer can't be reused.
///  2. **Confirm** — cream card stack (TriageView's stack, no drag): Every video / Sometimes / Leave it
///     out, with consequence microcopy. Answers are DURABLE (StyleJobStore sidecar) — a kill resumes at
///     the first unanswered card. "Leave it out" gets a 2.5s Undo chip; suppression is recoverable later
///     via the template's "Left out" footer.
///  3. **Outro** — hand-off to the editor ("get it on paper", not an overpromised cut).
///
/// Deliberately NO swipe-down-to-dismiss: the playbook's permanent rule binds full-screen *video
/// players*; a once-ever story moment must not be losable to a scroll reflex. Exits = the persistent
/// ≥44pt Skip + hold-to-pause. Skipping costs nothing irreversible (confirmations stay editable).
struct StyleRevealView: View {
    @Binding var template: StyleTemplate
    let firstName: String
    /// Refinement mode (M6): a diff makes this the MINI-reveal — wins announced first (headline slides,
    /// no generic script re-telling), then cards for NEW + CONTESTED signatures only.
    var diff: TemplateDiff? = nil
    var onDone: () -> Void

    private enum Phase: Equatable { case story, confirm, outro }
    @State private var phase: Phase = .story
    @State private var slideIndex = 0
    @State private var paused = false
    @State private var deck: [Card] = []               // STABLE snapshot taken on confirm entry — the
                                                       // computed `cards` shrinks as answers land, so
                                                       // index math runs on this, not on the live filter
    @State private var cardIndex = 0
    @State private var acceptingInput = false          // 400ms lockout so a story tap can't answer a card
    @State private var flash: String? = nil            // SF symbol for the commit flash
    @State private var undo: UndoState? = nil
    @State private var progress = StyleJobStore.RevealProgress()
    @State private var didHydrate = false

    private struct UndoState { let key: String; let apply: () -> Void }

    // MARK: - content model

    private enum Slide: Equatable {
        case text(String)
        case quote(String, attribution: String)
    }

    /// "Okay, Daniel." — or nothing when we don't know their name (never "Okay, there.").
    private var nameClause: String { firstName == "there" ? "" : ", \(firstName)" }

    private var slides: [Slide] {
        // MINI-reveal (refine): diff-only story — the user already knows who they are; this is about what
        // the new videos PROVED. Wins first, one summary, done.
        if let diff {
            var s: [Slide] = [.text("Okay\(nameClause).\nI watched \(diff.newVideoCount) more video\(diff.newVideoCount == 1 ? "" : "s").")]
            s += diff.headlines.map { .text($0) }
            s += diff.numericShifts.prefix(1).map { .text("One shift: \($0).") }
            s.append(.text(diff.summaryLine))
            return s
        }
        let n = max(1, template.count)
        var s: [Slide] = [.text("Okay\(nameClause).\nI watched your video\(n > 1 ? "s" : "").")]
        // Script lines — model-authored; derived fallback so old profiles still get a story. Budget:
        // N=1 (every onboarding user) stays tight — 3 lines + 1 quote; N≥2 earns the fuller set.
        let script = template.profile.revealScript.isEmpty ? derivedScript : template.profile.revealScript
        s += script.prefix(n > 1 ? 5 : 3).map { .text($0) }
        // Pull-quote slides — the creator's own words, huge. Spoken lines first, best evidence first.
        let quotable = template.profile.verbalStyle.recurringLines
            .filter { $0.confirmation != "out" && !$0.quote.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { a, b in
                if a.isSpoken != b.isSpoken { return a.isSpoken }
                return a.evidenceCount != b.evidenceCount ? a.evidenceCount > b.evidenceCount : a.likelyHabit > b.likelyHabit
            }
        for line in quotable.prefix(n > 1 ? 2 : 1) {
            let attribution = (n >= 2 && line.evidenceCount >= n)
                ? "— you, in all \(n) videos"
                : "— you, in this video"
            s.append(.quote(line.quote, attribution: attribution))
        }
        return s
    }

    /// Fallback narration when the profile predates reveal_script (framed by the fixed chrome).
    private var derivedScript: [String] {
        var lines: [String] = []
        let brief = template.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brief.isEmpty { lines.append(brief) }
        let hookDesc = template.profile.hook.description.trimmingCharacters(in: .whitespaces)
        if !hookDesc.isEmpty { lines.append("The way you open: \(hookDesc.prefix(1).lowercased() + hookDesc.dropFirst())") }
        let closing = template.profile.closing.description.trimmingCharacters(in: .whitespaces)
        if !closing.isEmpty { lines.append("And the way you land it: \(closing.prefix(1).lowercased() + closing.dropFirst())") }
        return lines.isEmpty ? ["Fast cuts, real reactions, food first — I've got the shape of it."] : lines
    }

    // MARK: confirm cards

    private enum CardKind: Equatable { case line(UUID), rating, signoff }
    private struct Card: Equatable {
        let kind: CardKind
        let eyebrow: String
        let quote: String
        let detail: String
        let key: String
    }

    private var cards: [Card] {
        let contested = Set(diff?.contested ?? [])
        var out: [Card] = []
        for line in template.profile.verbalStyle.recurringLines where line.confirmation == nil {
            let quote = line.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty else { continue }
            let isContested = contested.contains(line.key)
            let eyebrow: String = {
                if isContested { return "STILL YOUR THING?" }
                if line.medium == "text-overlay" { return "YOUR ON-SCREEN TEXT" }
                switch line.role {
                case "hook":     return "YOUR OPENER"
                case "verdict":  return "YOUR VERDICT LINE"
                case "sign-off": return "YOUR SIGN-OFF"
                default:         return "YOUR LINE"
                }
            }()
            let detail = isContested ? "Didn't hear it in the new videos." : line.deliveryNote
            out.append(Card(kind: .line(line.id), eyebrow: eyebrow, quote: quote,
                            detail: detail, key: line.key))
        }
        let vs = template.profile.verbalStyle
        let signoff = vs.signoff.trimmingCharacters(in: .whitespacesAndNewlines)
        if vs.signoffConfirmation == nil, !signoff.isEmpty,
           !out.contains(where: { $0.quote.lowercased() == signoff.lowercased() }),
           !template.profile.verbalStyle.recurringLines.contains(where: { $0.role == "sign-off" && $0.confirmation != nil }) {
            let isContested = contested.contains("__signoff__")
            out.append(Card(kind: .signoff, eyebrow: isContested ? "STILL YOUR THING?" : "YOUR SIGN-OFF",
                            quote: signoff, detail: isContested ? "Didn't hear it in the new videos." : "",
                            key: "__signoff__"))
        }
        let rating = vs.ratingFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        if vs.ratingConfirmation == nil, !rating.isEmpty {
            let isContested = contested.contains("__rating__")
            out.append(Card(kind: .rating,
                            eyebrow: isContested ? "STILL YOUR THING?" : (vs.ratingScope == "per-item" ? "YOUR RATING · EVERY DISH" : "YOUR RATING"),
                            quote: rating, detail: isContested ? "Didn't hear it in the new videos." : "",
                            key: "__rating__"))
        }
        // Mini-reveal asks ONLY about new + contested (they're exactly the unanswered set post-refiner);
        // fresh reveals cap tighter at N=1 (every onboarding user).
        return Array(out.prefix(diff != nil ? 6 : (max(1, template.count) > 1 ? 6 : 4)))
    }

    // MARK: - body

    var body: some View {
        ZStack {
            (phase == .story ? Color.veCharcoal : Color.veCream).ignoresSafeArea()

            switch phase {
            case .story:  storyPhase
            case .confirm: confirmPhase
            case .outro:  outroPhase
            }

            // Persistent Skip — ≥44pt target, top-right, all phases.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Log.app("🍳 Reveal skipped at phase=\(String(describing: phase)) slide=\(slideIndex) card=\(cardIndex).")
                        finish()
                    } label: {
                        Text("Skip")
                            .font(VeFont.sans(13, weight: .semibold))
                            .foregroundStyle(phase == .story ? Color.veCream.opacity(0.6) : Color.veWarmGray)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)

            // Commit flash (playbook confirmation grammar)
            if let flash {
                Image(systemName: flash)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(Color.veSage)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

            // Undo chip for "Leave it out"
            if undo != nil {
                VStack {
                    Spacer()
                    Button {
                        undo?.apply()
                        undo = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ToastView(text: "Left out — tap to undo")
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: flash != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: undo != nil)
        .animation(.easeInOut(duration: 0.45), value: slideIndex)
        .animation(.easeInOut(duration: 0.35), value: phase)
        .onAppear { hydrate() }
    }

    // MARK: - Phase 1 · story

    private var storyPhase: some View {
        let all = slides
        return ZStack {
            VStack(spacing: 0) {
                // Wrapped-style progress ticks
                HStack(spacing: 4) {
                    ForEach(0..<all.count, id: \.self) { i in
                        Capsule()
                            .fill(Color.veCream.opacity(i <= slideIndex ? 0.85 : 0.25))
                            .frame(height: 2.5)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 14)
                Spacer()
            }

            Group {
                if slideIndex < all.count {
                    slideView(all[slideIndex])
                        .id(slideIndex)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 30)

            // Tap zones: left third = back, right two-thirds = forward (standard story grammar).
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle())
                        .frame(width: geo.size.width / 3)
                        .onTapGesture { advance(-1) }
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { advance(1) }
                }
            }
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 60, perform: {},
                                onPressingChanged: { pressing in paused = pressing })
        }
        // Per-slide auto-advance: dwell scales with text length; suspended for VoiceOver and while held.
        .task(id: slideIndex) {
            guard !UIAccessibility.isVoiceOverRunning else { return }
            let chars: Int = {
                guard slideIndex < all.count else { return 0 }
                switch all[slideIndex] {
                case .text(let t): return t.count
                case .quote(let q, let a): return q.count + a.count
                }
            }()
            let dwell = min(5.5, max(2.8, 2.0 + 0.045 * Double(chars)))
            var elapsed: Double = 0
            while elapsed < dwell {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                if !paused { elapsed += 0.1 }
            }
            if phase == .story { advance(1) }
        }
    }

    @ViewBuilder
    private func slideView(_ slide: Slide) -> some View {
        switch slide {
        case .text(let line):
            Text(line)
                .font(VeFont.serif(27, italic: true))
                .foregroundStyle(Color.veCream)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .combine)
        case .quote(let quote, let attribution):
            VStack(spacing: 18) {
                Text("“")
                    .font(VeFont.serif(84))
                    .foregroundStyle(Color.veTerracotta)   // oversized glyph — decorative, contrast-exempt
                    .frame(height: 40)
                    .accessibilityHidden(true)
                Text(quote)
                    .font(VeFont.serif(30, italic: true))
                    .foregroundStyle(Color.veCream)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                // Attribution: cream at 0.75+, NEVER small terracotta on charcoal (3.3:1 fails small text).
                Text(attribution)
                    .font(VeFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.veCream.opacity(0.78))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func advance(_ delta: Int) {
        let all = slides
        let next = slideIndex + delta
        if next < 0 { return }
        if next >= all.count {
            enterConfirm()
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        slideIndex = next
    }

    private func enterConfirm() {
        progress.storyCompleted = true
        persist()
        deck = cards
        if deck.isEmpty {
            // No confirmable signatures (trend-chasing creators, style-in-the-edit) — no empty card stack.
            phase = .outro
            return
        }
        phase = .confirm
        cardIndex = 0
        acceptingInput = false
        Task { // 400ms lockout: a story tap-through must not land on a verdict button
            try? await Task.sleep(nanoseconds: 400_000_000)
            acceptingInput = true
        }
    }

    // MARK: - Phase 2 · confirm

    private var confirmPhase: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(diff != nil ? "A COUPLE TO DOUBLE-CHECK"
                     : (template.count > 1 ? "LOCK IN YOUR SIGNATURE" : "ONE VIDEO IN — IS THIS YOU EVERY TIME?"))
                    .font(VeFont.sans(11, weight: .bold)).tracking(1.3)
                    .foregroundStyle(Color.veTerracotta)
                    .multilineTextAlignment(.center)
                if !deck.isEmpty {
                    Text("\(min(cardIndex + 1, deck.count)) of \(deck.count)")
                        .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                }
            }
            .padding(.top, 66)

            Spacer()

            ZStack {
                // Peeking next card (stack affordance, no drag)
                if cardIndex + 1 < deck.count {
                    cardFace(deck[cardIndex + 1])
                        .scaleEffect(0.95)
                        .offset(y: 12)
                        .opacity(0.5)
                }
                if cardIndex < deck.count {
                    cardFace(deck[cardIndex])
                        .id(cardIndex)
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .padding(.horizontal, 26)

            Spacer()

            if cardIndex < deck.count {
                verdictButtons(for: deck[cardIndex])
                    .padding(.horizontal, 26)
                Text("Every video → I'll make sure every cut has it · Sometimes → I'll keep it when it shows up")
                    .font(VeFont.sans(11)).foregroundStyle(Color.veFaintGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 12)
                Text("The rest is on your template page.")
                    .font(VeFont.sans(11)).foregroundStyle(Color.veFaintGray.opacity(0.8))
                    .padding(.bottom, 26)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: cardIndex)
    }

    private func cardFace(_ card: Card) -> some View {
        VStack(spacing: 14) {
            Text(card.eyebrow)
                .font(VeFont.sans(10, weight: .bold)).tracking(1.2)
                .foregroundStyle(Color.veTerracotta)
            Text("“\(card.quote)”")
                .font(VeFont.serif(24, italic: true))
                .foregroundStyle(Color.veCharcoal)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 38).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.08), radius: 18, y: 8)
    }

    private func verdictButtons(for card: Card) -> some View {
        VStack(spacing: 9) {
            Button { answer(card, verdict: "every") } label: {
                Text("Every video")
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.veSage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            HStack(spacing: 9) {
                Button { answer(card, verdict: "sometimes") } label: {
                    Text("Sometimes")
                        .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Color.veSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { answer(card, verdict: "out") } label: {
                    Text("Leave it out")
                        .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veWarmGray)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Color.veCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.veWarmGray.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(!acceptingInput)
    }

    private func answer(_ card: Card, verdict: String) {
        guard acceptingInput else { return }
        acceptingInput = false

        apply(verdict: verdict, to: card)
        progress.answers[card.key] = verdict
        persist()

        // Feedback grammar: light for keeps, warning + undo chip for leave-out.
        if verdict == "out" {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let key = card.key
            undo = UndoState(key: key) { unapply(card) }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if undo?.key == key { undo = nil }
            }
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            flash = verdict == "every" ? "checkmark" : "checkmark.circle"
            Task {
                try? await Task.sleep(nanoseconds: 550_000_000)
                flash = nil
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            cardIndex += 1
            if cardIndex >= deck.count {
                phase = .outro
            } else {
                acceptingInput = true
            }
        }
    }

    private func apply(verdict: String, to card: Card) {
        switch card.kind {
        case .line(let id):
            if let i = template.profile.verbalStyle.recurringLines.firstIndex(where: { $0.id == id }) {
                template.profile.verbalStyle.recurringLines[i].confirmation = verdict
            }
            if verdict == "out" { suppress(card.key) }
        case .rating:
            if verdict == "out" { template.profile.verbalStyle.ratingFormat = "" ; template.profile.verbalStyle.ratingScope = "" }
            else { template.profile.verbalStyle.ratingConfirmation = verdict }
        case .signoff:
            if verdict == "out" { suppress(template.profile.verbalStyle.signoff); template.profile.verbalStyle.signoff = "" }
            else { template.profile.verbalStyle.signoffConfirmation = verdict }
        }
    }

    /// Undo for "Leave it out" — restores the exact pre-answer state and steps back to the undone card.
    private func unapply(_ card: Card) {
        switch card.kind {
        case .line(let id):
            if let i = template.profile.verbalStyle.recurringLines.firstIndex(where: { $0.id == id }) {
                template.profile.verbalStyle.recurringLines[i].confirmation = nil
            }
            unsuppress(card.key)
        case .rating:
            template.profile.verbalStyle.ratingFormat = card.quote
        case .signoff:
            template.profile.verbalStyle.signoff = card.quote
            unsuppress(card.quote)
        }
        progress.answers.removeValue(forKey: card.key)
        persist()
        if let i = deck.firstIndex(of: card) {
            cardIndex = i
            if phase == .outro { phase = .confirm }
            acceptingInput = true
        }
    }

    private func suppress(_ key: String) {
        let k = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !template.suppressed.contains(k) else { return }
        template.suppressed.append(k)
    }
    private func unsuppress(_ key: String) {
        let k = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        template.suppressed.removeAll { $0 == k }
    }

    // MARK: - Phase 3 · outro

    private var outroPhase: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(diff != nil
                 ? "Sharper already\(nameClause).\nSave it and it's live."
                 : (deck.isEmpty && template.profile.verbalStyle.recurringLines.isEmpty
                    ? "Your style lives in the edit, not a catchphrase\(nameClause) — I've got the pacing down."
                    : "That's your style\(nameClause).\nLet's get it on paper — tweak anything I got wrong."))
                .font(VeFont.serif(26, italic: true))
                .foregroundStyle(Color.veCharcoal)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 32)
            Spacer()
            PrimaryActionButton(title: "See my template") { finish() }
                .padding(.horizontal, 26).padding(.bottom, 34)
        }
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    // MARK: - lifecycle

    /// Resume support: re-apply persisted answers (kill mid-Reveal / back-navigation re-entry), skip the
    /// story if it was completed, and land on the first unanswered card — answered cards never replay.
    private func hydrate() {
        guard !didHydrate else { return }
        didHydrate = true
        guard let saved = StyleJobStore.loadRevealProgress() else { return }
        progress = saved
        for (key, verdict) in saved.answers {
            if key == "__rating__" {
                if verdict == "out" { template.profile.verbalStyle.ratingFormat = ""; template.profile.verbalStyle.ratingScope = "" }
                else { template.profile.verbalStyle.ratingConfirmation = verdict }
            } else if key == "__signoff__" {
                if verdict == "out" { suppress(template.profile.verbalStyle.signoff); template.profile.verbalStyle.signoff = "" }
                else { template.profile.verbalStyle.signoffConfirmation = verdict }
            } else if let i = template.profile.verbalStyle.recurringLines.firstIndex(where: { $0.key == key }) {
                template.profile.verbalStyle.recurringLines[i].confirmation = verdict
                if verdict == "out" { suppress(key) }
            }
        }
        if saved.storyCompleted {
            deck = cards   // only still-unanswered cards — answered ones never replay
            if deck.isEmpty { phase = .outro } else {
                phase = .confirm
                cardIndex = 0
                acceptingInput = false
                Task { try? await Task.sleep(nanoseconds: 400_000_000); acceptingInput = true }
            }
        }
    }

    private func persist() { StyleJobStore.saveRevealProgress(progress) }

    private func finish() {
        persist()
        onDone()
    }
}
