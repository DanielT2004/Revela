import SwiftUI

/// Onboarding step 1 — "How Vela works": three teaching beats between Welcome and Sign-up
/// (value before friction). Each page sells one value beat from the Maya Test:
///   0  the time collapse — hours of editing become minutes of deciding (ChaosToCutHero)
///   1  control — AI proposes, she disposes, via a REAL mini swipe deck (DemoDeckView)
///   2  the post-ready payoff — full-res 9:16, no watermark (ReadyToPostHero)
/// Skip is always visible and jumps straight to sign-up — never to home (they still need an account).
///
/// 🔒 Reset invariant: this flow keeps ZERO persistent state — page, deck progress, and the demo's
/// hint nudge are all transient `@State`, so `AuthStore.resetForTesting()` + `router.go(.onboarding)`
/// replays it from the very top with no extra keys to clear. If a future change adds an @AppStorage
/// flag here, it must also be removed in `resetForTesting()`.
struct HowItWorksView: View {
    let onComplete: () -> Void      // fires for BOTH finish and Skip → the sign-up step

    @State private var page = 0    // 0 promise, 1 demo, 2 payoff
    private static let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                Group {
                    switch page {
                    case 0:  promisePage
                    case 1:  demoPage
                    default: payoffPage
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: page)
            // The demo page's cards ARE horizontal swipes, so the pager swipe is masked off entirely
            // there (`.subviews` keeps the deck's own DragGesture alive) — you leave the demo by
            // finishing it or via Skip. Pages 0/2 also have buttons, so swipe is never the only path.
            .gesture(pageSwipe, including: page == 1 ? .subviews : .all)

            dots
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .background(Color.veCream.ignoresSafeArea())
    }

    // MARK: chrome

    /// Lives outside the transitioning ZStack so the label and Skip never animate away.
    private var topBar: some View {
        HStack(alignment: .center) {
            Text("HOW VELA WORKS")
                .font(VeFont.sans(11, weight: .heavy))
                .tracking(2.4)
                .foregroundStyle(Color.veWarmGray)
            Spacer()
            Button(action: onComplete) {
                Text("Skip")
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

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                if v.translation.width < -60, page < Self.pageCount - 1 { page += 1 }
                else if v.translation.width > 60, page > 0 { page -= 1 }
            }
    }

    // MARK: page 0 — the time collapse

    private var promisePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 10)
            ChaosToCutHero()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 26)

            Text("Hours of editing become minutes of deciding.")
                .font(VeFont.serif(32))
                .foregroundStyle(Color.veCharcoal)
                .lineSpacing(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text("Drop in your raw clips. Vela finds the hook, trims the dead air, and lays out your first cut — the timeline puzzle, already solved. You just decide what stays.")
                .font(VeFont.sans(15))
                .foregroundStyle(Color.veNoteText)
                .lineSpacing(3)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 14)

            Button { page = 1 } label: {
                Text("Next →")
                    .font(VeFont.sans(16, weight: .bold))
                    .foregroundStyle(Color.veCharcoal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.veCharcoal.opacity(0.08), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    // MARK: page 1 — control (the interactive demo)

    private var demoPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every cut is your call.")
                .font(VeFont.serif(30))
                .foregroundStyle(Color.veCharcoal)
                .minimumScaleFactor(0.85)

            Text("Vela proposes — you decide. Right to keep, left to cut, and nothing is ever deleted; cuts just wait in the tray. Go on, try these three:")
                .font(VeFont.sans(14.5))
                .foregroundStyle(Color.veNoteText)
                .lineSpacing(3)
                .padding(.top, 8)

            DemoDeckView { page = 2 }
                .padding(.top, 12)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    // MARK: page 2 — the post-ready payoff

    private var payoffPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 6)
            ReadyToPostHero()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 22)

            Text("Fine-tune it your way. Post it today.")
                .font(VeFont.serif(31))
                .foregroundStyle(Color.veCharcoal)
                .lineSpacing(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text("Reorder scenes, layer B-roll over your voice, crown your hook — then export a full-res 9:16 cut, no watermark, ready for TikTok.")
                .font(VeFont.sans(15))
                .foregroundStyle(Color.veNoteText)
                .lineSpacing(3)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 14)

            PrimaryActionButton(title: "Make it yours") { onComplete() }
                .padding(.top, 24)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }
}
