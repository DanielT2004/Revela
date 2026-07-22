import SwiftUI

/// The auto-playing hero dramatizations for the "How Vela works" onboarding pages.
/// Pure SwiftUI, sequenced with the house spring library via `.task` (cancels on disappear).
/// All heroes take `isActive` (the pager's current page) — they loop only while active and
/// show their settled end state otherwise (so a mid-drag glimpse of a neighbouring page looks
/// finished, not frozen mid-beat). Reduce Motion always renders the settled end state.

// MARK: - Page 0 hero — raw-clip chaos becomes the first cut (loops)

/// ~3s dramatization: scattered clips → a thin terracotta **scan line** sweeps left→right
/// (Vela watching), popping a verdict badge on each clip. As it crosses the trim tile, a
/// dashed trim line lands and the clip's dead-air half **breaks off and falls away** — the
/// trim, shown literally. Then keepers spring into a filmstrip (hook first, wearing its
/// pennant, "~2 min" chip) while cuts drift into a "Set aside" tray. Holds ~2.4s, falls
/// back apart, and replays — so nobody misses it.
struct ChaosToCutHero: View {
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var badged = false      // beat B: verdict badges pop in (staggered)
    @State private var trimLineOn = false  // beat B½: dashed trim line lands on the trim tile
    @State private var trimmed = false     // beat B½: the dead-air half breaks off
    @State private var assembled = false   // beat C: filmstrip assembles / cuts drift to tray
    @State private var trayShown = false   // "Set aside · 2" chip (after the cuts drift)
    @State private var scanX: CGFloat = -190
    @State private var scanOn = false
    @State private var pulse = false       // beat D: idle play-badge breathe

    private enum Verdict { case keep, cut, hook }
    private struct HeroTile {
        let tone: FoodTone
        let verdict: Verdict
        let rot: Double        // scattered rotation
        let off: CGSize        // scattered offset
        let slot: Int?         // filmstrip slot (nil for cuts)
        var trims: Bool = false
    }

    // Six clips dumped on the table. Slots: hook first, then the keeps. The char clip is
    // the trim demo: its right half is "dead air" that gets cut away mid-sequence.
    private let tiles: [HeroTile] = [
        .init(tone: .char,   verdict: .keep, rot: -13, off: .init(width: -104, height: -26), slot: 1, trims: true),
        .init(tone: .tomato, verdict: .hook, rot: 9,   off: .init(width: -38,  height: 22),  slot: 0),
        .init(tone: .talk,   verdict: .cut,  rot: -6,  off: .init(width: 18,   height: -34), slot: nil),
        .init(tone: .herb,   verdict: .keep, rot: 14,  off: .init(width: 66,   height: 18),  slot: 2),
        .init(tone: .cheese, verdict: .keep, rot: -9,  off: .init(width: 116,  height: -18), slot: 3),
        .init(tone: .plate,  verdict: .cut,  rot: 7,   off: .init(width: -68,  height: 40),  slot: nil),
    ]

    private func finalOffset(_ t: HeroTile) -> CGSize {
        if let slot = t.slot {
            // The trimmed tile's visible content is its left 30pt of a 52pt frame — nudge
            // right so the kept half sits centered in its slot.
            let x = -90 + CGFloat(slot) * 60 + (t.trims && trimmed ? 11 : 0)
            return CGSize(width: x, height: 0)
        }
        return CGSize(width: 0, height: 64)   // cuts sink toward the tray as they shrink away
    }

    var body: some View {
        VStack(spacing: 14) {
            // Micro-label crossfade: RAW → YOUR FIRST CUT (+ the hours-back chip).
            HStack(spacing: 8) {
                ZStack {
                    microLabel("YOUR RAW CLIPS", color: Color.veFaintGray).opacity(assembled ? 0 : 1)
                    microLabel("YOUR FIRST CUT", color: Color.veTerracotta).opacity(assembled ? 1 : 0)
                }
                Text("~2 min")
                    .font(VeFont.sans(9.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.veTerracotta, in: Capsule())
                    .opacity(assembled ? 1 : 0)
                    .scaleEffect(assembled ? 1 : 0.6)
            }
            .animation(.easeInOut(duration: 0.35), value: assembled)

            ZStack {
                ForEach(tiles.indices, id: \.self) { i in
                    let t = tiles[i]
                    tileView(t)
                        .rotationEffect(.degrees(assembled ? 0 : t.rot))
                        .offset(assembled ? finalOffset(t) : t.off)
                        .scaleEffect(assembled && t.verdict == .cut ? 0.25 : 1)
                        .opacity(assembled && t.verdict == .cut ? 0 : 1)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78)
                            .delay(Double(t.slot ?? 4) * 0.07), value: assembled)
                }

                // The scan line — Vela watching every second, made visible. A crisp 2pt
                // terracotta line with a short soft trail; hidden entirely between sweeps.
                ZStack {
                    LinearGradient(colors: [Color.veTerracotta.opacity(0), Color.veTerracotta.opacity(0.16)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 22, height: 150)
                        .offset(x: scanX - 12)
                    Rectangle()
                        .fill(Color.veTerracotta.opacity(0.75))
                        .frame(width: 2, height: 150)
                        .offset(x: scanX)
                }
                .opacity(scanOn ? 1 : 0)
                .allowsHitTesting(false)

                // "Set aside · 2" tray — the cuts wait, never deleted.
                HStack(spacing: 5) {
                    Image(systemName: "scissors").font(.system(size: 10, weight: .bold))
                    Text("Set aside · 2").font(VeFont.sans(11, weight: .bold))
                }
                .foregroundStyle(Color.veNoteText)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.veSurface, in: Capsule())
                .scaleEffect(trayShown ? 1 : 0.4)
                .opacity(trayShown ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: trayShown)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 178)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: Vela scans your scattered raw clips, trims the dead air out of one, and assembles an ordered first cut — hook first, cut clips set aside, never deleted.")
        .task(id: isActive) { await run() }
    }

    private func microLabel(_ text: String, color: Color) -> some View {
        Text(text).font(VeFont.sans(10.5, weight: .heavy)).tracking(1.8).foregroundStyle(color)
    }

    @ViewBuilder
    private func tileFace(_ t: HeroTile) -> some View {
        if t.trims {
            // Two-part tile: kept left 30pt + "dead air" right 22pt. The dead half dims,
            // breaks off, and falls away when the scan line lands the trim.
            HStack(spacing: 0) {
                FoodTile(tone: t.tone, cornerRadius: 0)
                    .frame(width: 30, height: 86)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10,
                                                      bottomTrailingRadius: trimmed ? 10 : 0,
                                                      topTrailingRadius: trimmed ? 10 : 0))
                FoodTile(tone: t.tone, cornerRadius: 0)
                    .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10))
                    .frame(width: 22, height: 86)
                    .opacity(trimmed ? 0 : 0.88)
                    .scaleEffect(trimmed ? 0.3 : 1, anchor: .top)
                    .offset(y: trimmed ? 34 : 0)
                    .animation(.easeIn(duration: 0.35), value: trimmed)
            }
            .overlay {
                if trimLineOn {
                    TrimDashLine()
                        .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 2, height: 86)
                        .offset(x: 4)   // the 30/22 junction, measured from the tile's centre
                        .transition(.opacity)
                }
            }
        } else {
            FoodTile(tone: t.tone, cornerRadius: 10)
        }
    }

    private func tileView(_ t: HeroTile) -> some View {
        tileFace(t)
            .frame(width: 52, height: 86)
            .shadow(color: Color.veCharcoal.opacity(0.10), radius: 8, y: 5)
            // Verdict badge (beat B), staggered left-to-right behind the scan line.
            .overlay(alignment: .topTrailing) {
                verdictBadge(t.verdict)
                    .scaleEffect(badged ? 1 : 0.01)
                    .opacity(badged ? 1 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7)
                        .delay(0.15 + (t.off.width + 120) / 240 * 0.8), value: badged)
                    .offset(x: 7, y: -7)
            }
            // Hook pennant + play-badge pulse once the strip has assembled (beat C/D).
            .overlay(alignment: .top) {
                if t.verdict == .hook && assembled {
                    Text("HOOK")
                        .font(VeFont.sans(8, weight: .bold)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Color.veTerracotta, in: Capsule())
                        .offset(y: -10)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .overlay {
                if t.verdict == .hook && assembled {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.3), in: Circle())
                        .scaleEffect(pulse ? 1.12 : 1.0)
                        .opacity(pulse ? 1 : 0.7)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
    }

    private func verdictBadge(_ v: Verdict) -> some View {
        let (icon, color): (String, Color) = {
            switch v {
            case .keep: return ("checkmark", Color.veSage)
            case .cut:  return ("scissors", Color.veTerracotta)
            case .hook: return ("star.fill", Color.veTerracotta)
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color, in: Circle())
            .shadow(color: color.opacity(0.35), radius: 4, y: 2)
    }

    // MARK: sequence

    private func settle() {
        badged = true; trimmed = true; trimLineOn = false; assembled = true; trayShown = true
        scanOn = false; pulse = false
    }

    private func resetInstant() {
        badged = false; trimmed = false; trimLineOn = false; assembled = false; trayShown = false
        scanX = -190; scanOn = false; pulse = false
    }

    private func run() async {
        guard isActive, !reduceMotion else { settle(); return }   // inactive pages glimpse the finished cut
        resetInstant()
        try? await Task.sleep(nanoseconds: 550_000_000)           // beat A: let the chaos read
        while !Task.isCancelled {
            await playOnce()
            try? await Task.sleep(nanoseconds: 2_400_000_000)     // hold the finished cut
            if Task.isCancelled { return }
            await resetForReplay()
            try? await Task.sleep(nanoseconds: 650_000_000)       // let the chaos read again
            if Task.isCancelled { return }
        }
    }

    private func playOnce() async {
        withAnimation(.easeInOut(duration: 0.9)) { scanX = 190 }    // beat B: the scan line…
        withAnimation(.easeInOut(duration: 0.15)) { scanOn = true }
        badged = true                                               // …pops badges (per-tile delays)
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.snappy(duration: 0.18)) { trimLineOn = true }   // the trim line lands…
        try? await Task.sleep(nanoseconds: 300_000_000)
        trimmed = true                                              // …and the dead air breaks off
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeInOut(duration: 0.25)) { scanOn = false }
        withAnimation(.easeOut(duration: 0.2)) { trimLineOn = false }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation { assembled = true }                          // beat C: strip assembles (per-tile delays)
        try? await Task.sleep(nanoseconds: 500_000_000)
        trayShown = true                                            // the cuts land in the tray
        try? await Task.sleep(nanoseconds: 400_000_000)             // beat D: idle breathe
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
    }

    /// The re-scatter is its own beat: the finished strip visibly falls back apart (and the
    /// trimmed clip grows its dead air back) before Vela "reads" it again.
    private func resetForReplay() async {
        withAnimation(.easeOut(duration: 0.2)) { pulse = false }    // replace the repeatForever
        trayShown = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
            assembled = false; badged = false; trimmed = false
        }
        scanX = -190
    }
}

/// A vertical dashed line (the trim cut) — Shape so it can take a dashed stroke style.
private struct TrimDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

// MARK: - Page 2 hero — Vela learns your style from posted videos (loops)

/// Three "posted video" tiles get the terracotta read sweep (the established "Vela watching"
/// verb), style-trait chips pop out, then fly down into an assembling YOUR STYLE template
/// card that finishes with an ACTIVE tag — echoing the real Home active-style card.
struct StyleLearnHero: View {
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tilesIn = false
    @State private var sweepX: CGFloat = -170
    @State private var sweepOn = false
    @State private var chipsPopped = false
    @State private var cardIn = false
    @State private var flown = false
    @State private var activeTag = false

    private struct TraitChip {
        let icon: String
        let text: String
        let italic: Bool
        let popped: CGSize     // position around the tiles (beat C)
        let slotY: CGFloat     // final row offset from the ZStack centre, inside the card body (beat D)
    }

    private let chips: [TraitChip] = [
        .init(icon: "bolt.fill",          text: "Fast cuts",     italic: false, popped: .init(width: -98, height: -138), slotY: 24),
        .init(icon: "person.crop.circle", text: "Talking hook",  italic: false, popped: .init(width: 98,  height: -132), slotY: 52),
        .init(icon: "square.on.square",   text: "B-roll heavy",  italic: false, popped: .init(width: -104, height: -28), slotY: 80),
        .init(icon: "quote.opening",      text: "\u{201C}okay wait, this is insane\u{201D}", italic: true,
              popped: .init(width: 96, height: -22), slotY: 108),
    ]

    private let tileTones: [FoodTone] = [.tomato, .cheese, .herb]

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                microLabel("YOUR POSTED VIDEOS", color: Color.veFaintGray).opacity(flown ? 0 : 1)
                microLabel("YOUR STYLE TEMPLATE", color: Color.veTerracotta).opacity(flown ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.35), value: flown)

            ZStack {
                // Beat A — three mini posted videos.
                HStack(spacing: 16) {
                    ForEach(tileTones.indices, id: \.self) { i in
                        FoodTile(tone: tileTones[i], cornerRadius: 9)
                            .frame(width: 44, height: 78)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 20, height: 20)
                                    .background(.black.opacity(0.28), in: Circle())
                            )
                            .shadow(color: Color.veCharcoal.opacity(0.10), radius: 7, y: 4)
                            .opacity(tilesIn ? 1 : 0)
                            .offset(y: tilesIn ? -78 : -68)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8)
                                .delay(Double(i) * 0.06), value: tilesIn)
                    }
                }

                // Beat B — the read sweep across the row.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color.veTerracotta.opacity(0), Color.veTerracotta.opacity(0.14), Color.veTerracotta.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 54, height: 96)
                    .offset(x: sweepX, y: -78)
                    .opacity(sweepOn ? 1 : 0)
                    .allowsHitTesting(false)

                // Beat D — the template card the chips fly into.
                templateCard
                    .offset(y: 56)
                    .scaleEffect(cardIn ? 1 : 0.9)
                    .opacity(cardIn ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: cardIn)

                // Beat C→D — trait chips: pop around the tiles, then fly into the card's body
                // as stacked rows. `slotY` is the chip's final offset from the ZStack centre,
                // placed below the card header (card spans y≈-32…+144; rows at 24…108).
                ForEach(chips.indices, id: \.self) { i in
                    let c = chips[i]
                    chipView(c)
                        .offset(flown ? CGSize(width: 0, height: c.slotY) : c.popped)
                        .scaleEffect(chipsPopped ? 1 : 0.01)
                        .opacity(chipsPopped ? 1 : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.72)
                            .delay(Double(i) * 0.09), value: chipsPopped)
                        .animation(.spring(response: 0.5, dampingFraction: 0.78)
                            .delay(Double(i) * 0.08), value: flown)
                }
            }
            .frame(height: 330)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: Vela studies your posted videos, pulls out your style traits, and builds your style template.")
        .task(id: isActive) { await run() }
    }

    private func microLabel(_ text: String, color: Color) -> some View {
        Text(text).font(VeFont.sans(10.5, weight: .heavy)).tracking(1.8).foregroundStyle(color)
    }

    private func chipView(_ c: TraitChip) -> some View {
        HStack(spacing: 5) {
            Image(systemName: c.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.veTerracotta)
            Text(c.text)
                .font(c.italic ? VeFont.serif(11.5, italic: true) : VeFont.sans(11, weight: .bold))
                .foregroundStyle(Color.veCharcoal)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white, in: Capsule())
        .shadow(color: Color.veCharcoal.opacity(0.10), radius: 6, y: 3)
    }

    private var templateCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.veTerracotta)
                Text("YOUR STYLE")
                    .font(VeFont.sans(10, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(Color.veWarmGray)
                Spacer()
                Text("ACTIVE")
                    .font(VeFont.sans(9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.veTerracotta, in: Capsule())
                    .scaleEffect(activeTag ? 1 : 0.4)
                    .opacity(activeTag ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: activeTag)
            }
            .padding(.horizontal, 14).padding(.top, 12)
            Spacer()
        }
        .frame(width: 262, height: 176)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.10), radius: 12, y: 7)
    }

    // MARK: sequence

    private func settle() {
        tilesIn = true; chipsPopped = true; cardIn = true; flown = true; activeTag = true
        sweepOn = false
    }

    private func resetInstant() {
        tilesIn = false; chipsPopped = false; cardIn = false; flown = false; activeTag = false
        sweepX = -170; sweepOn = false
    }

    private func run() async {
        guard isActive, !reduceMotion else { settle(); return }
        resetInstant()
        try? await Task.sleep(nanoseconds: 150_000_000)
        while !Task.isCancelled {
            await playOnce()
            try? await Task.sleep(nanoseconds: 2_400_000_000)     // hold the finished template
            if Task.isCancelled { return }
            await resetForReplay()
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
        }
    }

    private func playOnce() async {
        tilesIn = true                                             // beat A (per-tile delays)
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.easeInOut(duration: 0.2)) { sweepOn = true }   // beat B: Vela watches
        withAnimation(.easeInOut(duration: 0.85)) { sweepX = 170 }
        try? await Task.sleep(nanoseconds: 450_000_000)
        chipsPopped = true                                         // beat C (per-chip delays)
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.easeInOut(duration: 0.25)) { sweepOn = false }
        try? await Task.sleep(nanoseconds: 450_000_000)
        cardIn = true                                              // beat D: the template assembles
        try? await Task.sleep(nanoseconds: 200_000_000)
        flown = true                                               // chips fly into their rows
        try? await Task.sleep(nanoseconds: 750_000_000)
        activeTag = true
    }

    private func resetForReplay() async {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            flown = false; activeTag = false; cardIn = false
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeOut(duration: 0.3)) { chipsPopped = false; tilesIn = false }
        sweepX = -170
    }
}

// MARK: - Page 3 hero — a mini Polish editor, working (loops)

/// A stylized miniature of the real Polish page — preview on the mat, MAIN / B-ROLL / AUDIO
/// lanes under the fixed centered playhead — animating the things a real editor does: a clip
/// lifts and swaps position, a B-roll tile drops into its lane, the audio ducks with a volume
/// pill. Proof that Vela ends as a normal full editor, right in the app.
struct PolishMockHero: View {
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardIn = false
    @State private var lifted = false     // the char clip picks up…
    @State private var swapped = false    // …and swaps places with the herb clip
    @State private var brollIn = false    // B-roll tile drops into its lane
    @State private var ducked = false     // audio bars dip under the overlay
    @State private var volPill = false    // "vol 70%" pill

    // Pseudo-random waveform heights (fixed so the loop is stable).
    private let bars: [CGFloat] = [7, 11, 9, 13, 8, 12, 10, 14, 9, 12, 11, 8, 13, 10, 12, 9, 14, 8, 11, 13, 9, 10, 12, 8, 11, 9]
    private let duckRange = 8...17        // the bars under the B-roll overlay

    var body: some View {
        VStack(spacing: 14) {
            Text("A FULL EDITOR — RIGHT IN VELA")
                .font(VeFont.sans(10.5, weight: .heavy)).tracking(1.8)
                .foregroundStyle(Color.veTerracotta)

            editorCard
                .scaleEffect(cardIn ? 1 : 0.94)
                .opacity(cardIn ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: Vela's Polish editor — a real multi-track editor. Clips reorder, B-roll drops in, audio adjusts.")
        .task(id: isActive) { await run() }
    }

    // MARK: the mini editor

    private var editorCard: some View {
        VStack(spacing: 10) {
            // Mini preview on the mat, like the real Polish page.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.vePreviewMat)
                    .frame(height: 96)
                FoodTile(tone: .tomato, cornerRadius: 8)
                    .frame(width: 48, height: 84)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.3), in: Circle())
            }

            // The 3-lane timeline under a fixed centered playhead.
            ZStack {
                VStack(spacing: 6) {
                    laneRow(tag: "MAIN", height: 30) { mainLane }
                    laneRow(tag: "B-ROLL", height: 24) { brollLane }
                    laneRow(tag: "AUDIO", height: 20) { audioLane }
                }
                // The Polish signature: the fixed centered playhead the timeline lives under.
                Rectangle()
                    .fill(Color.veTerracotta)
                    .frame(width: 2, height: 106)
                    .offset(x: 22)   // half the gutter width, so it centers over the lanes
                    .allowsHitTesting(false)
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.10), radius: 14, y: 8)
        .frame(maxWidth: 340)
    }

    private func laneRow<C: View>(tag: String, height: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(VeFont.sans(8, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Color.veWarmGray)
                .frame(width: 36, alignment: .leading)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.veTrackLane)
                    .frame(height: height)
                content()
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Three clips; the char clip lifts and swaps places with the herb clip (the reorder).
    private var mainLane: some View {
        let xA: CGFloat = 6
        let xB: CGFloat = swapped ? 126 : 66
        let xC: CGFloat = swapped ? 66 : 126
        return ZStack(alignment: .leading) {
            clipTile(.tomato, width: 54).offset(x: xA)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.veTerracotta, in: Circle())
                        .offset(x: xA + 2, y: -4)
                }
            clipTile(.char, width: 54)
                .scaleEffect(lifted ? 1.14 : 1)
                .shadow(color: Color.veCharcoal.opacity(lifted ? 0.28 : 0), radius: 7, y: 4)
                .offset(x: xB, y: lifted ? -4 : 0)
                .zIndex(2)
            clipTile(.herb, width: 54).offset(x: xC)
        }
        .frame(height: 24)
    }

    private var brollLane: some View {
        ZStack(alignment: .leading) {
            if brollIn {
                clipTile(.cheese, width: 44, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color(hex: 0x9A7350), lineWidth: 1.5))
                    .offset(x: 82)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(height: 18)
    }

    private var audioLane: some View {
        HStack(spacing: 2.5) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.veSage.opacity(0.55))
                    .frame(width: 3, height: ducked && duckRange.contains(i) ? bars[i] * 0.45 : bars[i])
            }
        }
        .padding(.leading, 8)
        .frame(height: 20, alignment: .center)
        // The volume pill — "adjusting the audio," made visible.
        .overlay(alignment: .trailing) {
            Text("vol 70%")
                .font(VeFont.sans(8.5, weight: .bold))
                .foregroundStyle(Color.veCharcoal)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.white, in: Capsule())
                .shadow(color: Color.veCharcoal.opacity(0.12), radius: 4, y: 2)
                .scaleEffect(volPill ? 1 : 0.4)
                .opacity(volPill ? 1 : 0)
                .offset(x: -4, y: -14)
        }
    }

    private func clipTile(_ tone: FoodTone, width: CGFloat, height: CGFloat = 24) -> some View {
        FoodTile(tone: tone, cornerRadius: 5)
            .frame(width: width, height: height)
    }

    // MARK: sequence

    private func settle() {
        cardIn = true; lifted = false; swapped = true; brollIn = true; ducked = true; volPill = true
    }

    private func resetInstant() {
        cardIn = false; lifted = false; swapped = false; brollIn = false; ducked = false; volPill = false
    }

    private func run() async {
        guard isActive, !reduceMotion else { settle(); return }
        resetInstant()
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { cardIn = true }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lifted = true }      // pick up…
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { swapped = true }     // …drag over…
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { lifted = false }     // …drop
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { brollIn = true }    // B-roll lands
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { ducked = true }                          // audio ducks
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { volPill = true }
            try? await Task.sleep(nanoseconds: 2_400_000_000)                                   // hold
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.3)) { volPill = false; ducked = false }          // reset beats
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.3)) { brollIn = false }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { swapped = false }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
        }
    }
}
