import SwiftUI
import UIKit

/// The onboarding mini swipe deck — three sample cards the user actually swipes, so the core
/// Sort gesture is learned by doing it (and the app's best moment is felt before sign-up).
/// Mirrors TriageView's numbers exactly (thresholds, rotation, flash, hint nudge) with no
/// video, no store, and no persistence: the hint replays every run — a demo should always demo.
struct DemoDeckView: View {
    /// Fires ~0.9s after the last card commits (the done beat plays first).
    let onFinished: () -> Void

    @State private var index = 0
    @State private var dragOffset: CGSize = .zero
    @State private var flashKeep: Bool?     // nil = no flash
    @State private var kept = 0             // for the done line
    @State private var deckIn = false       // entrance: stack slides up before the hint plays
    @State private var finished = false     // guards double-fire if the user re-enters mid-beat

    private let cards: [DemoCard] = [
        .init(id: 0, tone: .char, chip: "SIZZLE", caption: "Steak hits the hot pan",
              duration: "4s", verdict: "Strong keep", verdictIcon: "star.fill",
              verdictTone: Color.veSage, lean: 1),
        .init(id: 1, tone: .talk, chip: "TALKING", caption: "\u{201C}Wait\u{2014} let me start over\u{201D}",
              duration: "6s", verdict: "Suggested cut", verdictIcon: "scissors",
              verdictTone: Color.veTerracotta, lean: -1),
        .init(id: 2, tone: .cheese, chip: "PLATING", caption: "The pull, up close",
              duration: "3s", verdict: "Keeper", verdictIcon: "checkmark",
              verdictTone: Color.veSage, lean: 1),
    ]

    private var isDone: Bool { index >= cards.count }

    var body: some View {
        GeometryReader { geo in
            let cardHeight = max(240, geo.size.height - 26)
            ZStack {
                if isDone {
                    doneBeat
                } else {
                    backPlaceholder(height: cardHeight, inset: 26, yOffset: 18, opacity: 0.45)
                        .opacity(index < cards.count - 2 ? 1 : 0)
                    backPlaceholder(height: cardHeight, inset: 13, yOffset: 9, opacity: 0.75)
                        .opacity(index < cards.count - 1 ? 1 : 0)

                    DemoCardView(card: cards[index], height: cardHeight, dragOffset: dragOffset)
                        .id(cards[index].id)   // fresh card view per index → hint re-arms
                        .gesture(dragGesture)
                }
                if let keep = flashKeep { flashView(keep).zIndex(999) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxHeight: .infinity)
        // Entrance: the whole stack rises into place before the first hint nudge fires.
        .opacity(deckIn ? 1 : 0)
        .offset(y: deckIn ? 0 : 24)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { deckIn = true }
        }
    }

    // MARK: gesture + commit (TriageView parity)

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { v in
                if v.translation.width > 95 { commit(keep: true) }
                else if v.translation.width < -95 { commit(keep: false) }
                else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = .zero }
                }
            }
    }

    /// Either direction is valid on every card — the lesson is "you decide", not "guess right".
    private func commit(keep: Bool) {
        if keep {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            kept += 1
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        withAnimation(.snappy(duration: 0.2)) { flashKeep = keep }
        withAnimation(.easeIn(duration: 0.26)) {
            dragOffset = CGSize(width: keep ? 700 : -700, height: 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            dragOffset = .zero
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { index += 1 }
            if index >= cards.count && !finished {
                finished = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onFinished() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) { flashKeep = nil }
        }
    }

    // MARK: pieces

    private func backPlaceholder(height: CGFloat, inset: CGFloat, yOffset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .padding(.horizontal, inset)
            .frame(height: height)
            .offset(y: yOffset)
            .shadow(color: Color.veCharcoal.opacity(0.08), radius: 10, y: 6)
            .allowsHitTesting(false)
    }

    private func flashView(_ keep: Bool) -> some View {
        Image(systemName: keep ? "checkmark" : "xmark")
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .background(keep ? Color.veSage : Color.veTerracotta, in: Circle())
            .shadow(color: (keep ? Color.veSage : Color.veTerracotta).opacity(0.4), radius: 16, y: 6)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private var doneBeat: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.veSage).frame(width: 64, height: 64)
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            }
            Text("That's the whole job.").font(VeFont.serif(24)).foregroundStyle(Color.veCharcoal)
            Text("You kept \(kept), cut \(cards.count - kept) — in seconds, not an afternoon.")
                .font(VeFont.sans(13.5)).foregroundStyle(Color.veWarmGray)
                .multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

// MARK: - card model

private struct DemoCard: Identifiable {
    let id: Int
    let tone: FoodTone
    let chip: String
    let caption: String
    let duration: String
    let verdict: String
    let verdictIcon: String
    let verdictTone: Color
    let lean: CGFloat        // hint-nudge direction: +1 keep-suggested, -1 cut-suggested
}

// MARK: - one demo card

private struct DemoCardView: View {
    let card: DemoCard
    let height: CGFloat
    let dragOffset: CGSize

    /// One-shot swipe hint (first card only): slide toward the suggested side, spring back to rest.
    @State private var hint: CGFloat = 0

    private var leanFactor: CGFloat { max(0, 1 - hypot(dragOffset.width, dragOffset.height) / 120) }
    private var hintX: CGFloat { card.lean * 60 * hint * leanFactor }
    private var hintDegrees: Double { Double(card.lean) * 5 * Double(hint) * Double(leanFactor) }

    private var keepOpacity: Double { dragOffset.width > 0 ? min(1, dragOffset.width / 90) : 0 }
    private var cutOpacity: Double { dragOffset.width < 0 ? min(1, -dragOffset.width / 90) : 0 }
    private var isIdle: Bool { dragOffset == .zero }

    var body: some View {
        VStack(spacing: 0) {
            hero
            footer
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.16), radius: 18, y: 14)
        .offset(x: dragOffset.width + hintX, y: dragOffset.height)
        .rotationEffect(.degrees(Double(dragOffset.width) * 0.04 + hintDegrees))
        .onAppear(perform: playHint)
    }

    private func playHint() {
        guard card.id == 0 else { return }
        withAnimation(.easeInOut(duration: 0.42).delay(0.35)) { hint = 1 }      // slide out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.77) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { hint = 0 }   // spring back
        }
    }

    private var hero: some View {
        ZStack {
            FoodTile(tone: card.tone, cornerRadius: 0)

            // caption band — the exact TriageCardView treatment
            VStack {
                Spacer()
                Text(card.caption)
                    .font(VeFont.serif(15, italic: true))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(LinearGradient(colors: [.black.opacity(0.5), .clear],
                                               startPoint: .bottom, endPoint: .top))
            }

            // AI verdict chip — the proposal she's disposing of
            HStack(spacing: 5) {
                Image(systemName: card.verdictIcon).font(.system(size: 10.5, weight: .bold))
                Text(card.verdict).font(VeFont.sans(11.5, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(card.verdictTone.opacity(0.92), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)

            // idle direction pills — just the two core verbs
            ZStack {
                hintPill("← CUT").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 10)
                hintPill("KEEP →").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 10)
            }
            .allowsHitTesting(false)
            .opacity(isIdle ? 1 : 0)

            // live swipe badges
            badge("KEEP", color: Color.veSage, rotation: 8, opacity: keepOpacity, alignment: .topTrailing)
            badge("CUT", color: Color.veTerracotta, rotation: -8, opacity: cutOpacity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var footer: some View {
        HStack(spacing: 9) {
            SceneChip(text: card.chip)
            Spacer()
            Text(card.duration)
                .font(VeFont.sans(12.5, weight: .semibold)).foregroundStyle(Color.veWarmGray)
        }
        .padding(15)
    }

    private func hintPill(_ text: String) -> some View {
        Text(text)
            .font(VeFont.sans(10.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.black.opacity(0.32), in: Capsule())
    }

    private func badge(_ text: String, color: Color, rotation: Double, opacity: Double, alignment: Alignment) -> some View {
        Text(text)
            .font(VeFont.sans(15, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
