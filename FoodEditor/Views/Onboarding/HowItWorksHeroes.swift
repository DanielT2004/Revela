import SwiftUI

/// The two auto-playing hero dramatizations for the "How Vela works" onboarding pages.
/// Pure SwiftUI, sequenced with the house spring library via `.task` (cancels on disappear).
/// Both respect Reduce Motion by rendering their settled end state without the sequence.

// MARK: - Page 0 hero — raw-clip chaos becomes the first cut

/// ~3s one-shot: scattered clips → a warm "read" sweep pops a verdict badge on each →
/// keepers spring into a filmstrip (hook lands first, wearing its pennant) while cuts
/// drift into a visible "Set aside" tray — footage never lost, shown not told.
struct ChaosToCutHero: View {
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
        .task { await run() }
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

    private func run() async {
        guard !reduceMotion else {   // settled end state, no theatrics
            badged = true; assembled = true; trayShown = true
            return
        }
        try? await Task.sleep(nanoseconds: 550_000_000)          // beat A: let the chaos read
        withAnimation(.easeInOut(duration: 0.9)) { sweepX = 190 }   // beat B: the read sweep…
        withAnimation(.easeInOut(duration: 0.2)) { sweepOn = true }
        badged = true                                            // …pops badges (per-tile delays)
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeInOut(duration: 0.25)) { sweepOn = false }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation { assembled = true }                       // beat C: strip assembles (per-tile delays)
        try? await Task.sleep(nanoseconds: 500_000_000)
        trayShown = true                                         // the cuts land in the tray
        try? await Task.sleep(nanoseconds: 400_000_000)          // beat D: idle breathe
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
    }
}

// MARK: - Page 2 hero — a post assembles inside a 9:16 frame

/// A mini phone frame builds the finished post: base clip → B-roll overlay → caption →
/// "Ready for TikTok". The three editor beats (Arrange / Polish / Post) stagger in below.
struct ReadyToPostHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var frameIn = false
    @State private var brollIn = false
    @State private var captionIn = false
    @State private var readyIn = false
    @State private var beatsIn = false

    var body: some View {
        VStack(spacing: 22) {
            phoneFrame
            beatChips
        }
        .task { await run() }
    }

    private var phoneFrame: some View {
        ZStack {
            // Mat + base clip filling the 9:16 frame edge-to-edge.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.vePreviewMat)
            FoodTile(tone: .tomato, cornerRadius: 24)
                .padding(5)

            // B-roll overlay landing on the upper third — the Polish lane, made visible.
            FoodTile(tone: .cheese, cornerRadius: 8)
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

    private func run() async {
        guard !reduceMotion else {
            frameIn = true; brollIn = true; captionIn = true; readyIn = true; beatsIn = true
            return
        }
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
