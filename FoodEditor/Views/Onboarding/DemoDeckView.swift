import SwiftUI
import UIKit

/// The onboarding demo — a guided four-swipe sequence with zero reading. Cards are bare food
/// tiles; each accepts exactly ONE direction (right = keep, left = cut, up = hook, down =
/// B-roll), taught by the hint nudge + a single edge pill. The show is the mini timeline
/// below: every swipe visibly moves the clip — into its slot, the set-aside tray, the front
/// of the cut (hook), or the overlay lane (B-roll) — with a one-line coach caption narrating.
/// Gesture numbers mirror TriageView exactly. No persistence: replays fresh every activation.
struct DemoDeckView: View {
    /// The pager's current-page flag — the deck resets and re-teaches each time it becomes active.
    var isActive: Bool = true
    /// Fires ~0.9s after the last card commits (the done beat plays first).
    let onFinished: () -> Void

    @State private var index = 0
    @State private var dragOffset: CGSize = .zero
    @State private var flash: DemoAction?
    @State private var deckIn = false       // entrance: stack slides up before the hint plays
    @State private var finished = false     // guards double-fire

    // The mini timeline (the "behind the scenes" state).
    @State private var spine: [SpineTile] = []      // lane 1 — the cut, in order
    @State private var brollLane: [SpineTile] = []  // lane 2 — overlays
    @State private var setAside = 0                 // the trash count
    @State private var cutFlight: SpineTile?        // transient: the clip flying into the trash
    @State private var coachLine: String?

    /// The fixed teaching sequence: simple verbs first, the two wow verbs last.
    private let cards: [DemoCard] = [
        .init(id: 0, tone: .char,   action: .keep),
        .init(id: 1, tone: .talk,   action: .cut),
        .init(id: 2, tone: .tomato, action: .hook),
        .init(id: 3, tone: .herb,   action: .broll),
    ]

    private var isDone: Bool { index >= cards.count }

    var body: some View {
        VStack(spacing: 12) {
            // ── the deck ──
            GeometryReader { geo in
                let cardHeight = max(200, geo.size.height - 26)
                ZStack {
                    if isDone {
                        doneBeat
                    } else {
                        backPlaceholder(height: cardHeight, inset: 26, yOffset: 18, opacity: 0.45)
                            .opacity(index < cards.count - 2 ? 1 : 0)
                        backPlaceholder(height: cardHeight, inset: 13, yOffset: 9, opacity: 0.75)
                            .opacity(index < cards.count - 1 ? 1 : 0)

                        DemoCardView(card: cards[index], height: cardHeight, dragOffset: dragOffset,
                                     onAccessibilityCommit: { commit(cards[index].action) })
                            .id(cards[index].id)   // fresh card view per step → hint re-arms
                            .gesture(dragGesture)
                    }
                    if let flash { flashView(flash).zIndex(999) }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .frame(maxHeight: .infinity)
            .opacity(deckIn ? 1 : 0)
            .offset(y: deckIn ? 0 : 24)

            // ── the timeline: what the swipes are doing behind the scenes ──
            SpineStripView(spine: spine, brollLane: brollLane, setAside: setAside,
                           cutFlight: cutFlight, total: cards.count)

            // ── the coach line narrating the last move ──
            ZStack {
                if let coachLine {
                    Text(coachLine)
                        .font(VeFont.serif(13.5, italic: true))
                        .foregroundStyle(Color.veNoteText)
                        .id(coachLine)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
            .frame(height: 18)
            .animation(.easeOut(duration: 0.3), value: coachLine)
        }
        .onAppear { if isActive { restart() } }
        .onChange(of: isActive) { _, active in
            if active { restart() }
        }
    }

    /// Fresh lesson every activation — a demo should always demo.
    private func restart() {
        index = 0; dragOffset = .zero; flash = nil; finished = false
        spine = []; brollLane = []; setAside = 0; coachLine = nil
        deckIn = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { deckIn = true }
    }

    // MARK: gesture + commit (TriageView parity; only the required direction lands)

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                let required = cards[index].action
                if hits(required, dx: dx, dy: dy) {
                    commit(required)
                } else {
                    // Wrong direction (or not far enough): snap back — the nudge is the correction.
                    let crossedAnother = DemoAction.allCases.contains { hits($0, dx: dx, dy: dy) }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = .zero }
                    if crossedAnother { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                }
            }
    }

    private func hits(_ action: DemoAction, dx: CGFloat, dy: CGFloat) -> Bool {
        switch action {
        case .keep:  return dx > 95
        case .cut:   return dx < -95
        case .hook:  return dy < -110 && abs(dy) > abs(dx)
        case .broll: return dy > 110 && abs(dy) > abs(dx)
        }
    }

    private func commit(_ action: DemoAction) {
        action.haptic()
        let tile = SpineTile(id: cards[index].id, tone: cards[index].tone, isHook: action == .hook)
        withAnimation(.snappy(duration: 0.2)) { flash = action }
        withAnimation(.easeIn(duration: 0.26)) { dragOffset = action.exitOffset }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            dragOffset = .zero
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                switch action {
                case .keep:  spine.append(tile)
                case .cut:   setAside += 1
                case .hook:  spine.insert(tile, at: 0)
                case .broll: brollLane.append(tile)
                }
                index += 1
            }
            withAnimation(.easeOut(duration: 0.3)) { coachLine = action.coachLine }
            UIAccessibility.post(notification: .announcement, argument: action.coachLine)
            if action == .cut {
                // The clip visibly flies into the trash can at the strip's trailing edge.
                cutFlight = tile
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { cutFlight = nil }
            }
            if index >= cards.count && !finished {
                finished = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onFinished() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) { flash = nil }
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

    private func flashView(_ action: DemoAction) -> some View {
        Image(systemName: action.flashIcon)
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .background(action.color, in: Circle())
            .shadow(color: action.color.opacity(0.4), radius: 16, y: 6)
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
            Text("Hook up front, B-roll layered over — you just built the cut.")
                .font(VeFont.sans(13.5)).foregroundStyle(Color.veWarmGray)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

// MARK: - the four demo verbs

private enum DemoAction: CaseIterable {
    case keep, cut, hook, broll

    var badge: String {
        switch self {
        case .keep: return "KEEP";    case .cut: return "CUT"
        case .hook: return "★ HOOK";  case .broll: return "↓ B-ROLL"
        }
    }
    var pill: String {
        switch self {
        case .keep: return "KEEP →";  case .cut: return "← CUT"
        case .hook: return "↑ HOOK";  case .broll: return "↓ B-ROLL"
        }
    }
    var color: Color {
        switch self {
        case .keep: return Color.veSage;     case .cut: return Color.veTerracotta
        case .hook: return Color.veCharcoal; case .broll: return Color(hex: 0x9A7350)
        }
    }
    var flashIcon: String {
        switch self {
        case .keep: return "checkmark";  case .cut: return "xmark"
        case .hook: return "star.fill";  case .broll: return "square.on.square"
        }
    }
    var exitOffset: CGSize {
        switch self {
        case .keep:  return CGSize(width: 700, height: 60)
        case .cut:   return CGSize(width: -700, height: 60)
        case .hook:  return CGSize(width: 0, height: -900)
        case .broll: return CGSize(width: 0, height: 900)
        }
    }
    /// Hint-nudge direction (unit vector; 60pt horizontal / 45pt vertical amplitudes).
    var lean: CGSize {
        switch self {
        case .keep:  return CGSize(width: 1, height: 0)
        case .cut:   return CGSize(width: -1, height: 0)
        case .hook:  return CGSize(width: 0, height: -1)
        case .broll: return CGSize(width: 0, height: 1)
        }
    }
    var coachLine: String {
        switch self {
        case .keep:  return "Added to your cut."
        case .cut:   return "Cut. It waits in the tray — nothing's ever deleted."
        case .hook:  return "Your new opener — moved to the very front."
        case .broll: return "Layered over the cut — it plays while your voice continues."
        }
    }
    var verbPhrase: (direction: String, verb: String) {
        switch self {
        case .keep:  return ("right", "keep it")
        case .cut:   return ("left", "cut it")
        case .hook:  return ("up", "make it the hook")
        case .broll: return ("down", "mark it as B-roll")
        }
    }
    func haptic() {
        switch self {
        case .keep:  UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .cut:   UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .hook:  UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .broll: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

private struct DemoCard: Identifiable {
    let id: Int
    let tone: FoodTone
    let action: DemoAction
}

private struct SpineTile: Identifiable {
    let id: Int
    let tone: FoodTone
    var isHook = false
}

// MARK: - one demo card (bare tile + one instruction)

private struct DemoCardView: View {
    let card: DemoCard
    let height: CGFloat
    let dragOffset: CGSize
    /// VoiceOver path: the single custom action performs the required swipe without dragging.
    let onAccessibilityCommit: () -> Void

    /// One-shot swipe hint toward the card's required direction; replays after idle
    /// (the patient teacher taps the table again). 0 at rest, →1 at full nudge.
    @State private var hint: CGFloat = 0

    private var leanFactor: CGFloat { max(0, 1 - hypot(dragOffset.width, dragOffset.height) / 120) }
    private var hintX: CGFloat { card.action.lean.width * 60 * hint * leanFactor }
    private var hintY: CGFloat { card.action.lean.height * 45 * hint * leanFactor }
    private var hintDegrees: Double { Double(card.action.lean.width) * 5 * Double(hint) * Double(leanFactor) }

    private var isIdle: Bool { dragOffset == .zero }
    private var isVertical: Bool { abs(dragOffset.height) > abs(dragOffset.width) }

    /// How strongly the (only) drag badge shows — ramps in as they drag the required way.
    private var badgeOpacity: Double {
        let dx = dragOffset.width, dy = dragOffset.height
        switch card.action {
        case .keep:  return (!isVertical && dx > 0) ? min(1, dx / 90) : 0
        case .cut:   return (!isVertical && dx < 0) ? min(1, -dx / 90) : 0
        case .hook:  return (isVertical && dy < 0) ? min(1, -dy / 100) : 0
        case .broll: return (isVertical && dy > 0) ? min(1, dy / 100) : 0
        }
    }
    private var badgeAlignment: Alignment {
        switch card.action {
        case .keep: return .topTrailing;  case .cut: return .topLeading
        case .hook: return .top;          case .broll: return .bottom
        }
    }
    private var badgeRotation: Double {
        switch card.action {
        case .keep: return 8;  case .cut: return -8
        case .hook, .broll: return 0
        }
    }
    private var pillAlignment: Alignment {
        switch card.action {
        case .keep: return .trailing;  case .cut: return .leading
        case .hook: return .top;       case .broll: return .bottom
        }
    }
    private var pillPadding: EdgeInsets {
        switch card.action {
        case .keep:  return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12)
        case .cut:   return EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        case .hook:  return EdgeInsets(top: 14, leading: 0, bottom: 0, trailing: 0)
        case .broll: return EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0)
        }
    }

    var body: some View {
        ZStack {
            FoodTile(tone: card.tone, cornerRadius: 0)

            // The single instruction — on the edge they'll swipe toward (idle only).
            Text(card.action.pill)
                .font(VeFont.sans(12, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(.black.opacity(0.32), in: Capsule())
                .padding(pillPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pillAlignment)
                .opacity(isIdle ? 1 : 0)
                .allowsHitTesting(false)

            // The confirming badge, ramping in as the drag approaches the threshold.
            Text(card.action.badge)
                .font(VeFont.sans(15, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(card.action.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .rotationEffect(.degrees(badgeRotation))
                .opacity(badgeOpacity)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: badgeAlignment)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.16), radius: 18, y: 14)
        .offset(x: dragOffset.width + hintX, y: dragOffset.height + hintY)
        .rotationEffect(.degrees(Double(dragOffset.width) * 0.04 + hintDegrees))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample clip — swipe \(card.action.verbPhrase.direction) to \(card.action.verbPhrase.verb)")
        .accessibilityAction(named: Text(card.action.badge.capitalized)) { onAccessibilityCommit() }
        .task(id: card.id) {
            // Nudge on arrival, then re-nudge while the card sits untouched.
            while !Task.isCancelled {
                if isIdle { playHint() }
                try? await Task.sleep(nanoseconds: 3_200_000_000)
            }
        }
    }

    private func playHint() {
        withAnimation(.easeInOut(duration: 0.42).delay(0.35)) { hint = 1 }      // slide out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.77) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { hint = 0 }   // spring back
        }
    }
}

// MARK: - the mini timeline (lane 1 = the cut, lane 2 = B-roll overlays, plus the tray)

private struct SpineStripView: View {
    let spine: [SpineTile]
    let brollLane: [SpineTile]
    let setAside: Int
    let cutFlight: SpineTile?
    let total: Int

    private var emptySlots: Int { max(0, total - spine.count - brollLane.count - setAside) }
    private var changeKey: String { "\(spine.map(\.id))-\(brollLane.count)-\(setAside)" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            stripBody
            // The cut clip arcs into the trash — deletion made explicit (it still waits
            // in the tray in the real app; the coach line says so).
            if let f = cutFlight {
                CutFlightTile(tone: f.tone).id(f.id)
            }
        }
    }

    private var stripBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("YOUR CUT")
                    .font(VeFont.sans(10.5, weight: .heavy)).tracking(1.8)
                    .foregroundStyle(Color.veFaintGray)
                Spacer()
                if setAside > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .symbolEffect(.bounce, value: setAside)
                        Text("\(setAside)").font(VeFont.sans(11, weight: .bold))
                    }
                    .foregroundStyle(Color.veNoteText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.veSurface, in: Capsule())
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(height: 26)

            // Lane 1 — the cut. Hook wears its pennant; undecided clips are dashed slots.
            HStack(spacing: 6) {
                ForEach(spine) { tile in
                    FoodTile(tone: tile.tone, cornerRadius: 8)
                        .frame(width: 34, height: 54)
                        .overlay {
                            if tile.isHook {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.veTerracotta, lineWidth: 2)
                            }
                        }
                        .overlay(alignment: .top) {
                            if tile.isHook {
                                Text("HOOK")
                                    .font(VeFont.sans(7.5, weight: .bold)).tracking(0.5)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.veTerracotta, in: Capsule())
                                    .offset(y: -9)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .scale(scale: 0.6)).combined(with: .opacity))
                }
                ForEach(0..<emptySlots, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.veFaintGray.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 34, height: 54)
                }
            }
            .padding(.top, 6)   // room for the HOOK pennant to sit proud of its tile

            // Lane 2 — the overlay track, underlapping the cut like a second layer.
            HStack(spacing: 6) {
                Text("B-ROLL")
                    .font(VeFont.sans(9, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(Color(hex: 0x9A7350))
                    .opacity(brollLane.isEmpty ? 0.35 : 1)
                ForEach(brollLane) { tile in
                    FoodTile(tone: tile.tone, cornerRadius: 7)
                        .frame(width: 30, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(hex: 0x9A7350), lineWidth: 2))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.leading, 40)
            .frame(height: 46, alignment: .center)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: changeKey)
    }
}

/// The transient mini clip that shrinks into the trash chip after a cut-swipe.
private struct CutFlightTile: View {
    let tone: FoodTone
    @State private var flown = false

    var body: some View {
        FoodTile(tone: tone, cornerRadius: 7)
            .frame(width: 30, height: 46)
            .scaleEffect(flown ? 0.15 : 1)
            .opacity(flown ? 0 : 1)
            .offset(x: flown ? -8 : -170, y: flown ? 6 : 52)
            .onAppear { withAnimation(.easeIn(duration: 0.45)) { flown = true } }
            .allowsHitTesting(false)
    }
}
