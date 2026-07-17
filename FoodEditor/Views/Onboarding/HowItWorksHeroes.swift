import SwiftUI

/// The auto-playing hero dramatizations for the "How Vela works" onboarding pages.
/// Pure SwiftUI, sequenced with the house spring library via `.task` (cancels on disappear).
/// All heroes take `isActive` (the pager's current page) — they loop only while active and
/// show their settled end state otherwise (so a mid-drag glimpse of a neighbouring page looks
/// finished, not frozen mid-beat). Reduce Motion always renders the settled end state.

// MARK: - Page 0 hero — raw-clip chaos becomes the first cut (loops)

/// ~3s dramatization: scattered clips → a warm "read" sweep pops a verdict badge on each →
/// keepers spring into a filmstrip (hook lands first, wearing its pennant) while cuts
/// drift into a visible "Set aside" tray. Holds the finished cut ~2.4s, falls back apart,
/// and replays — so nobody misses it.
struct ChaosToCutHero: View {
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var badged = false      // beat B: verdict badges pop in (staggered)
    @State private var assembled = false   // beat C: filmstrip assembles / cuts drift to tray
    @State private var trayShown = false   // "Set aside · 2" chip (after the cuts drift)
    @State private var sweepX: CGFloat = -190
    @State private var sweepOn = false
    @State private var pulse = false       // beat D: idle play-badge breathe

    private enum Verdict { case keep, cut, hook }
    private struct HeroTile {
        let tone: FoodTone
        let verdict: Verdict
        let rot: Double        // scattered rotation
        let off: CGSize        // scattered offset
        let slot: Int?         // filmstrip slot (nil for cuts)
    }

    // Six clips dumped on the table. Slots: hook first, then the keeps.
    private let tiles: [HeroTile] = [
        .init(tone: .char,   verdict: .keep, rot: -13, off: .init(width: -104, height: -26), slot: 1),
        .init(tone: .tomato, verdict: .hook, rot: 9,   off: .init(width: -38,  height: 22),  slot: 0),
        .init(tone: .talk,   verdict: .cut,  rot: -6,  off: .init(width: 18,   height: -34), slot: nil),
        .init(tone: .herb,   verdict: .keep, rot: 14,  off: .init(width: 66,   height: 18),  slot: 2),
        .init(tone: .cheese, verdict: .keep, rot: -9,  off: .init(width: 116,  height: -18), slot: 3),
        .init(tone: .plate,  verdict: .cut,  rot: 7,   off: .init(width: -68,  height: 40),  slot: nil),
    ]

    private func finalOffset(_ t: HeroTile) -> CGSize {
        if let slot = t.slot { return CGSize(width: -90 + CGFloat(slot) * 60, height: 0) }
        return CGSize(width: 0, height: 64)   // cuts sink toward the tray as they shrink away
    }

    var body: some View {
        VStack(spacing: 14) {
            // Micro-label crossfade: RAW → YOUR FIRST CUT.
            ZStack {
                microLabel("YOUR RAW CLIPS", color: Color.veFaintGray).opacity(assembled ? 0 : 1)
                microLabel("YOUR FIRST CUT", color: Color.veTerracotta).opacity(assembled ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.35), value: assembled)

            ZStack {
                ForEach(tiles.indices, id: \.self) { i in
                    let t = tiles[i]
                    tileView(t, index: i)
                        .rotationEffect(.degrees(assembled ? 0 : t.rot))
                        .offset(assembled ? finalOffset(t) : t.off)
                        .scaleEffect(assembled && t.verdict == .cut ? 0.25 : 1)
                        .opacity(assembled && t.verdict == .cut ? 0 : 1)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78)
                            .delay(Double(t.slot ?? 4) * 0.07), value: assembled)
                }

                // The warm "read" sweep — Gemini watching every second, made visible.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color.veTerracotta.opacity(0), Color.veTerracotta.opacity(0.14), Color.veTerracotta.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 60, height: 150)
                    .offset(x: sweepX)
                    .opacity(sweepOn ? 1 : 0)
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
        .accessibilityLabel("Animation: scattered raw clips become an ordered first cut — hook first, cut clips set aside, never deleted.")
        .task(id: isActive) { await run() }
    }

    private func microLabel(_ text: String, color: Color) -> some View {
        Text(text).font(VeFont.sans(10.5, weight: .heavy)).tracking(1.8).foregroundStyle(color)
    }

    private func tileView(_ t: HeroTile, index: Int) -> some View {
        FoodTile(tone: t.tone, cornerRadius: 10)
            .frame(width: 52, height: 86)
            .shadow(color: Color.veCharcoal.opacity(0.10), radius: 8, y: 5)
            // Verdict badge (beat B), staggered left-to-right behind the sweep.
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
        badged = true; assembled = true; trayShown = true
        sweepOn = false; pulse = false
    }

    private func resetInstant() {
        badged = false; assembled = false; trayShown = false
        sweepX = -190; sweepOn = false; pulse = false
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
        withAnimation(.easeInOut(duration: 0.9)) { sweepX = 190 }   // beat B: the read sweep…
        withAnimation(.easeInOut(duration: 0.2)) { sweepOn = true }
        badged = true                                               // …pops badges (per-tile delays)
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeInOut(duration: 0.25)) { sweepOn = false }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation { assembled = true }                          // beat C: strip assembles (per-tile delays)
        try? await Task.sleep(nanoseconds: 500_000_000)
        trayShown = true                                            // the cuts land in the tray
        try? await Task.sleep(nanoseconds: 400_000_000)             // beat D: idle breathe
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
    }

    /// The re-scatter is its own beat: the finished strip visibly falls back apart before
    /// Vela "reads" it again.
    private func resetForReplay() async {
        withAnimation(.easeOut(duration: 0.2)) { pulse = false }    // replace the repeatForever
        trayShown = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { assembled = false; badged = false }
        sweepX = -190
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

// MARK: - Page 3 hero — the cut they built, assembling inside a 9:16 frame

/// A mini phone frame builds the finished post: base clip → B-roll overlay → caption →
/// "Ready for TikTok". When the user completed the swipe demo, the micro-label says so —
/// they finish onboarding having MADE this cut (the tones match the demo's hook/B-roll cards).
struct ReadyToPostHero: View {
    var builtByUser: Bool = false
    var isActive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var frameIn = false
    @State private var brollIn = false
    @State private var captionIn = false
    @State private var readyIn = false
    @State private var beatsIn = false

    var body: some View {
        VStack(spacing: 18) {
            Text(builtByUser ? "THE CUT YOU JUST BUILT" : "READY TO POST")
                .font(VeFont.sans(10.5, weight: .heavy)).tracking(1.8)
                .foregroundStyle(builtByUser ? Color.veTerracotta : Color.veFaintGray)
            phoneFrame
            beatChips
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: your finished cut assembles in a vertical frame — B-roll layered on, caption added, ready for TikTok. Then: arrange, polish, post.")
        .task(id: isActive) { await run() }
    }

    private var phoneFrame: some View {
        ZStack {
            // Mat + base clip filling the 9:16 frame edge-to-edge. Tones mirror the demo:
            // tomato = the hook card, herb = the B-roll card — continuity with what they built.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.vePreviewMat)
            FoodTile(tone: .tomato, cornerRadius: 24)
                .padding(5)

            // B-roll overlay landing on the upper third — the Polish lane, made visible.
            FoodTile(tone: .herb, cornerRadius: 8)
                .frame(width: 52, height: 66)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(hex: 0x9A7350), lineWidth: 2))
                .shadow(color: Color.veCharcoal.opacity(0.3), radius: 8, y: 5)
                .scaleEffect(brollIn ? 1 : 0.5)
                .opacity(brollIn ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 22).padding(.trailing, 14)

            // Serif-italic caption on the caption gradient — her voice on the frame.
            VStack {
                Spacer()
                Text("the pull, up close")
                    .font(VeFont.serif(12, italic: true))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 22)
                    .background(LinearGradient(colors: [.black.opacity(0.45), .clear],
                                               startPoint: .bottom, endPoint: .top))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(5)
            .opacity(captionIn ? 1 : 0)
            .offset(y: captionIn ? 0 : 8)
        }
        .frame(width: 150, height: 267)
        .shadow(color: Color.veCharcoal.opacity(0.14), radius: 16, y: 10)
        .shadow(color: Color.veSage.opacity(readyIn ? 0.28 : 0), radius: 18, y: 4)
        // "Ready for TikTok" chip overlapping the frame's corner — the payoff.
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.veSage)
                Text("Ready for TikTok")
                    .font(VeFont.sans(11.5, weight: .bold))
                    .foregroundStyle(Color.veCharcoal)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color.white, in: Capsule())
            .shadow(color: Color.veCharcoal.opacity(0.14), radius: 8, y: 4)
            .scaleEffect(readyIn ? 1 : 0.4)
            .opacity(readyIn ? 1 : 0)
            .offset(x: 26, y: 10)
        }
        .scaleEffect(frameIn ? 1 : 0.92)
        .opacity(frameIn ? 1 : 0)
    }

    private var beatChips: some View {
        HStack(spacing: 14) {
            beatChip(icon: "arrow.up.arrow.down", title: "Arrange", caption: "drag the order", idx: 0)
            beatChip(icon: "square.on.square", title: "Polish", caption: "B-roll & captions", idx: 1)
            beatChip(icon: "arrow.up.right.square", title: "Post", caption: "full-res, no watermark", idx: 2)
        }
    }

    private func beatChip(icon: String, title: String, caption: String, idx: Int) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.veTerracotta)
                .frame(width: 40, height: 40)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.veCharcoal.opacity(0.07), radius: 5, y: 3)
            Text(title).font(VeFont.sans(12, weight: .bold)).foregroundStyle(Color.veCharcoal)
            Text(caption).font(VeFont.sans(10.5)).foregroundStyle(Color.veWarmGray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .opacity(beatsIn ? 1 : 0)
        .offset(y: beatsIn ? 0 : 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(idx) * 0.06), value: beatsIn)
    }

    private func settle() {
        frameIn = true; brollIn = true; captionIn = true; readyIn = true; beatsIn = true
    }

    private func run() async {
        guard isActive, !reduceMotion else { settle(); return }
        frameIn = false; brollIn = false; captionIn = false; readyIn = false; beatsIn = false
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { frameIn = true }
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { brollIn = true }
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.easeOut(duration: 0.35)) { captionIn = true }
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { readyIn = true }
        try? await Task.sleep(nanoseconds: 250_000_000)
        beatsIn = true   // per-chip delays handle the stagger
    }
}
