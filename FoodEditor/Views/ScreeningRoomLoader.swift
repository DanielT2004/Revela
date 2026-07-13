import SwiftUI
import UIKit

/// **The Screening Room** — the style-learn loader: filmstrip rows of the creator's real frames drifting
/// laterally under a warm reading lens that studies frame after frame, like an editor going through their
/// tape. All motion is `TimelineView(.animation)`-driven transforms (offset/position/opacity) — GPU-
/// composited, never Canvas — because the learn's compress exports are competing for CPU (same rule as
/// `ColumnDriftLoader`). Purely decorative: the status block below it narrates for VoiceOver.
struct ScreeningRoomLoader: View {
    let thumbnails: [UIImage]                        // real frames; empty → FoodTile gradient fallback
    var stage: StyleAnalysisCoordinator.LearnStage
    var progress: Double                             // Reduce Motion highlight position
    var analyzedCount: Int
    var totalCount: Int
    var paused: Bool                                 // not running / backgrounded → freeze the clock
    var pulseDate: Date? = nil                       // M3: one-beat lens brighten per analyzed video

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows = 3
    private let tileSize = CGSize(width: 52, height: 72)
    private let tileGap: CGFloat = 8
    private let rowSpacing: CGFloat = 10
    private let speed: Double = 12                   // pt/s — calmer than ColumnDrift's 20 (horizontal reads faster)

    var body: some View {
        GeometryReader { geo in
            SwiftUI.TimelineView(.animation(minimumInterval: nil, paused: paused || reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let lensPoint = lensPosition(t: t, size: geo.size)
                ZStack {
                    VStack(spacing: rowSpacing) {
                        ForEach(0..<rows, id: \.self) { r in
                            filmstrip(r, width: geo.size.width, t: t, lens: lensPoint)
                        }
                    }
                    if !reduceMotion {
                        lens(at: lensPoint, t: t)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) { slateCounter.padding(10) }
        .accessibilityHidden(true)   // decorative — the status block below narrates stage + progress
    }

    // MARK: filmstrip rows

    private func filmstrip(_ r: Int, width: CGFloat, t: Double, lens: CGPoint) -> some View {
        let slotW = tileSize.width + tileGap
        let visible = Int(ceil(width / slotW)) + 2
        // Alternating direction per row; floor() keeps slot math correct for negative scroll.
        let scroll = t * speed * (r % 2 == 0 ? 1 : -1)
        let firstSlot = Int(floor(scroll / slotW))
        let rowHeight = tileSize.height + 16
        let rowMidY = rowCenterY(r)

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.veCharcoal.opacity(0.05))
            SprocketRule().padding(.horizontal, 8).offset(y: -rowHeight / 2 + 5)
            SprocketRule().padding(.horizontal, 8).offset(y: rowHeight / 2 - 5)

            ForEach(firstSlot..<(firstSlot + visible), id: \.self) { slot in
                let x = CGFloat(slot) * slotW - scroll + tileSize.width / 2 + tileGap / 2
                let proximity = reduceMotion ? reduceMotionHighlight(slot: slot, row: r)
                                             : lensProximity(tileX: x, tileY: rowMidY, lens: lens)
                frameTile(contentIndex: slot &* rows &+ r, proximity: proximity)
                    .position(x: x, y: rowHeight / 2)
            }
        }
        .frame(height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// One frame of the creator's footage (or a warm gradient placeholder). `proximity` (0…1) is how
    /// close the reading lens is — a brightness lift + an ochre "read" tick, computed per frame with no
    /// per-tile state.
    private func frameTile(contentIndex: Int, proximity: Double) -> some View {
        Group {
            if !thumbnails.isEmpty {
                let count = thumbnails.count
                Image(uiImage: thumbnails[((contentIndex % count) + count) % count])
                    .resizable().scaledToFill()
            } else {
                FoodTile(tone: FoodTone.tone(for: abs(contentIndex)), cornerRadius: 8)
            }
        }
        .frame(width: tileSize.width, height: tileSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.14 * proximity))
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(hex: 0x9A7350))
                .frame(width: 4, height: 4)
                .padding(4)
                .opacity(proximity > 0.55 ? 1 : 0)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.45) : nil, value: proximity > 0.55)
    }

    private func lensProximity(tileX: CGFloat, tileY: CGFloat, lens: CGPoint) -> Double {
        let dx = abs(tileX - lens.x)
        guard dx < 44 else { return 0 }
        return Double(1 - dx / 44)
    }

    /// Reduce Motion: no lens — one steadily-advancing highlighted tile per row keyed off real progress.
    private func reduceMotionHighlight(slot: Int, row: Int) -> Double {
        let slots = 7
        let lit = Int(progress * Double(slots)) % slots
        let wrapped = ((slot % slots) + slots) % slots
        return wrapped == lit ? 0.8 : 0
    }

    // MARK: the reading lens

    /// Cadence by stage: prep — slow room-scan; watching — dwell-then-glide, frame to frame, stepping a
    /// row every pass; synthesizing — settles center and breathes.
    private func lensPosition(t: Double, size: CGSize) -> CGPoint {
        switch stage {
        case .compressing, .uploading:
            let x = size.width * 0.5 + CGFloat(sin(t * 0.35)) * size.width * 0.38
            let y = size.height * 0.5 + CGFloat(sin(t * 0.21)) * size.height * 0.28
            return CGPoint(x: x, y: y)
        case .watching:
            let beat = t / 2.4                                    // one frame studied per beat
            let step = floor(beat)
            let frac = beat - step
            let glide = frac < 0.72 ? 0.0 : smoothstep((frac - 0.72) / 0.28)
            let u = (step + glide).truncatingRemainder(dividingBy: 5) / 5
            let row = abs(Int(floor(step / 5))) % rows
            return CGPoint(x: size.width * (0.10 + 0.80 * CGFloat(u)),
                           y: rowCenterY(row))
        case .synthesizing:
            let y = size.height * 0.5 + CGFloat(sin(t * 0.8)) * 6
            return CGPoint(x: size.width * 0.5, y: y)
        }
    }

    private func rowCenterY(_ r: Int) -> CGFloat {
        let rowHeight = tileSize.height + 16
        return (rowHeight + rowSpacing) * CGFloat(r) + rowHeight / 2
    }

    private func lens(at point: CGPoint, t: Double) -> some View {
        // M3 settle-beat: a brief brighten right as a video finishes analyzing.
        let pulseBoost: Double = {
            guard let pulseDate else { return 0 }
            let dt = Date().timeIntervalSince(pulseDate)
            return dt >= 0 && dt < 0.8 ? (1 - dt / 0.8) * 0.5 : 0
        }()
        return RadialGradient(colors: [Color(hex: 0x9A7350).opacity(0.30 + 0.3 * pulseBoost),
                                       Color.veTerracotta.opacity(0.12 + 0.12 * pulseBoost),
                                       .clear],
                              center: .center, startRadius: 6, endRadius: 95)
            .frame(width: 190, height: 190)
            .position(point)
            .allowsHitTesting(false)
    }

    private func smoothstep(_ x: Double) -> Double {
        let c = max(0, min(1, x))
        return c * c * (3 - 2 * c)
    }

    // MARK: slate counter

    private var slateCounter: some View {
        Text("VIDEO \(min(max(analyzedCount, 1), max(totalCount, 1))) OF \(max(totalCount, 1))")
            .font(VeFont.mono(11, weight: .semibold)).tracking(1)
            .foregroundStyle(Color.veWarmGray)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.veCream.opacity(0.85), in: Capsule())
    }
}

/// The film-edge sprocket dots: a dashed round-cap line — 0.5pt dashes at 9pt spacing read as a row of
/// perforations without any per-dot views.
private struct SprocketRule: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(Color.veCharcoal.opacity(0.12),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.5, 9]))
        }
        .frame(height: 3)
    }
}
