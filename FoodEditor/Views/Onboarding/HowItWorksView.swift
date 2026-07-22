import SwiftUI

/// "How Vela works" — four teaching beats, each selling one value from the Maya Test:
///   0  the time collapse — hours of editing become minutes of deciding (ChaosToCutHero, loops)
///   1  control — a guided four-swipe demo with a live mini timeline (DemoDeckView)
///   2  the moat — Vela learns your style and builds your template (StyleLearnHero, loops)
///   3  the payoff — the cut you just built, post-ready (ReadyToPostHero) → CTA
///
/// Used two ways: onboarding step 1 (Welcome → HERE → Sign up; Skip/CTA both continue to
/// sign-up) and as a replayable tour from Profile (`mode: .replay` — "Done"/"Got it" dismiss).
/// Pages live in a finger-tracking pager (1:1 drag, rubber-band edges, spring settle);
/// paging is fully masked on the demo page, whose cards own all four swipe directions.
///
/// 🔒 Reset invariant: this flow keeps ZERO persistent state — page, deck progress, and the
/// hint nudges are all transient `@State`, so `AuthStore.resetForTesting()` +
/// `router.go(.onboarding)` replays it from the very top with no extra keys to clear. If a
/// future change adds an @AppStorage flag here, it must also be removed in `resetForTesting()`.
struct HowItWorksView: View {
    enum Mode { case onboarding, replay }

    var mode: Mode = .onboarding
    let onComplete: () -> Void      // onboarding: → sign-up (finish AND Skip). replay: dismiss.

    @State private var page = 0    // 0 promise, 1 demo, 2 style, 3 payoff, 4 founder note
    @State private var dragX: CGFloat = 0
    @State private var dragging = false
    private static let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    promisePage.frame(width: w)
                    demoPage.frame(width: w)
                    stylePage.frame(width: w)
                    payoffPage.frame(width: w)
                    founderPage.frame(width: w)
                }
                .offset(x: -CGFloat(page) * w + dragX)
                .animation(dragging ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: page)
                .animation(dragging ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: dragX)
                // The demo page's cards own ALL four swipe directions, so the pager gesture is
                // masked off entirely there (`.subviews`) — you leave the demo by finishing it,
                // via Skip, or by the style page's back-swipe later. Pages 0/2/3 also have
                // buttons, so swipe is never the only path.
                .gesture(pagerDrag(width: w), including: page == 1 ? .subviews : .all)
            }
            .clipped()

            dots
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .background(Color.veCream.ignoresSafeArea())
    }

    // MARK: pager

    private func pagerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if !dragging {
                    guard abs(dx) > abs(dy) else { return }   // respect direction
                    dragging = true
                }
                // Rubber-band past either end — the page follows at 1/3 strength.
                let atEdge = (page == 0 && dx > 0) || (page == Self.pageCount - 1 && dx < 0)
                dragX = atEdge ? dx / 3 : dx
            }
            .onEnded { v in
                guard dragging else { return }
                dragging = false
                let dx = v.translation.width
                let predicted = v.predictedEndTranslation.width
                var next = page
                if dx < -width / 4 || predicted < -width / 2 { next = min(page + 1, Self.pageCount - 1) }
                else if dx > width / 4 || predicted > width / 2 { next = max(page - 1, 0) }
                page = next
                dragX = 0
            }
    }

    // MARK: chrome

    /// Lives outside the pager so the label and Skip/Done never move with the pages.
    private var topBar: some View {
        HStack(alignment: .center) {
            Text("HOW VELA WORKS")
                .font(VeFont.sans(11, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(Color.veWarmGray)
            Spacer()
            Button(action: onComplete) {
                Text(mode == .replay ? "Done" : "Skip")
                    .font(VeFont.sans(13.5, weight: .semibold))
                    .foregroundStyle(Color.veWarmGray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.top, 14)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.veTerracotta : Color.veFaintGray.opacity(0.35))
                    .frame(width: i == page ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
    }

    /// The quiet secondary CTA (pages 0/2/3) — the terracotta primary is saved for the
    /// founder's note (the last beat before the sign-up ask).
    private func nextButton(to target: Int) -> some View {
        Button { page = target } label: {
            Text("Next →")
                .font(VeFont.sans(16, weight: .bold))
                .foregroundStyle(Color.veCharcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.veCharcoal.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Scroll-safety for the copy/note pages: content stays centered when it fits, scrolls
    /// instead of clipping on small phones. NOT used on the demo page (vertical swipes).
    private func pageScroll<C: View>(@ViewBuilder _ content: @escaping () -> C) -> some View {
        GeometryReader { g in
            ScrollView(showsIndicators: false) {
                content()
                    .frame(maxWidth: .infinity, minHeight: g.size.height)
            }
        }
    }

    // MARK: page 0 — the time collapse

    private var promisePage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 10)
                ChaosToCutHero(isActive: page == 0)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 26)

                Text("Your editor. If it did the boring half — and knew your style.")
                    .font(VeFont.serif(32))
                    .foregroundStyle(Color.veCharcoal)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text("You already spend hours trimming dead air and hunting for the hook. Vela does that first pass in your style, then hands you the cut to approve — so editing becomes minutes of deciding, not hours.")
                    .font(VeFont.sans(15))
                    .foregroundStyle(Color.veNoteText)
                    .lineSpacing(3)
                    .frame(maxWidth: 322, alignment: .leading)
                    .padding(.top, 14)

                nextButton(to: 1)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 8)
        }
    }

    // MARK: page 1 — control (the guided demo)

    private var demoPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every cut is your call.")
                .font(VeFont.serif(30))
                .foregroundStyle(Color.veCharcoal)
                .minimumScaleFactor(0.85)

            Text("Vela roughed out the cut — but every call is still yours. Give it a try, no account needed:")
                .font(VeFont.sans(14.5))
                .foregroundStyle(Color.veNoteText)
                .lineSpacing(3)
                .padding(.top, 8)

            DemoDeckView(isActive: page == 1) { page = 2 }
                .padding(.top, 12)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    // MARK: page 2 — the moat (style learning)

    private var stylePage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 6)
                StyleLearnHero(isActive: page == 2)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 20)

                Text("It edits like you. Because it learned from you.")
                    .font(VeFont.serif(30))
                    .foregroundStyle(Color.veCharcoal)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Show Vela a video you've already posted and it learns your hooks, your pacing, your catchphrases — your style template, the recipe for how you edit — so every new video comes out sounding like you. And it keeps learning from every cut you approve.")
                    .font(VeFont.sans(14.5))
                    .foregroundStyle(Color.veNoteText)
                    .lineSpacing(3)
                    .frame(maxWidth: 330, alignment: .leading)
                    .padding(.top, 12)

                nextButton(to: 3)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 8)
        }
    }

    // MARK: page 3 — the post-ready payoff

    private var payoffPage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 6)
                PolishMockHero(isActive: page == 3)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 20)

                Text("Fine-tune it your way. Post it today.")
                    .font(VeFont.serif(31))
                    .foregroundStyle(Color.veCharcoal)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Vela isn't just the first pass — it's a full editor, too. Reorder scenes, layer B-roll over your voice, crown your hook, all right here in Vela. Then export a 9:16 cut that's ready for TikTok.")
                    .font(VeFont.sans(15))
                    .foregroundStyle(Color.veNoteText)
                    .lineSpacing(3)
                    .frame(maxWidth: 322, alignment: .leading)
                    .padding(.top, 12)

                Text("No watermark · No credits · Full-res always")
                    .font(VeFont.sans(12, weight: .semibold))
                    .foregroundStyle(Color.veWarmGray)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                nextButton(to: 4)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 8)
        }
    }

    // MARK: page 4 — a note from the founder (the "feel human" beat before the ask)

    private var founderPage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)
                founderNote
                Spacer(minLength: 24)

                PrimaryActionButton(title: mode == .replay ? "Got it" : "Make it yours") { onComplete() }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 8)
        }
    }

    private var founderNote: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A NOTE FROM THE FOUNDER")
                .font(VeFont.sans(11, weight: .heavy)).tracking(2.0)
                .foregroundStyle(Color.veWarmGray)

            Text("I'm Daniel. I built Vela on nights and weekends, because editing my own videos was eating the hours I'd rather spend making them.\n\nI wanted an editor that does the boring first pass and actually learns how I like things — so I made one.\n\nThanks for giving it a shot. I hope it gives you your hours back.")
                .font(VeFont.serif(16))
                .foregroundStyle(Color.veNoteText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            // Serif-italic signature with a small hand-drawn terracotta flourish.
            VStack(alignment: .leading, spacing: 2) {
                Text("Daniel")
                    .font(VeFont.serif(26, italic: true))
                    .foregroundStyle(Color.veCharcoal)
                SignatureFlourish()
                    .stroke(Color.veTerracotta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 92, height: 12)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.veCharcoal.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.veCharcoal.opacity(0.06), radius: 10, y: 5)
    }
}

/// A small hand-drawn underline swoosh under the founder's signature.
private struct SignatureFlourish: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + 2))
        p.addCurve(to: CGPoint(x: rect.maxX * 0.62, y: rect.midY - 1),
                   control1: CGPoint(x: rect.maxX * 0.2, y: rect.maxY),
                   control2: CGPoint(x: rect.maxX * 0.4, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY + 3),
                   control1: CGPoint(x: rect.maxX * 0.8, y: rect.midY - 3),
                   control2: CGPoint(x: rect.maxX * 0.92, y: rect.minY + 1))
        return p
    }
}
