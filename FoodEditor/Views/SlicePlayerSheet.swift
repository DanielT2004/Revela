import SwiftUI
import UIKit
import AVFoundation

/// Plays (and gently loops) a single [start, end] slice of the merged proxy. Presented as a `.sheet`
/// so the system gives interactive swipe-down-to-dismiss for free (per the full-screen-video rule).
/// Shared by the post-analysis recap (`FirstCutView`) and Triage (`TriageView`).
///
/// Transport: a controls-free `PlayerLayerView` (we own the player), a **drag-to-scrub** bar along the
/// bottom, and **press-and-hold anywhere on the video for a 2× fast preview** (Meka #12). A downward
/// swipe cancels the hold, so the sheet's swipe-down-to-dismiss stays intact.
struct SlicePlayerSheet: View {
    let url: URL
    let start: Double
    let end: Double
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var observer: Any?
    @State private var progress: Double = 0      // 0…1 within [start, end]
    @State private var scrubbing = false
    @State private var fastForward = false

    private var span: Double { max(0.05, end - start) }
    private var startTime: CMTime { CMTime(seconds: max(0, start), preferredTimescale: 600) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.veCharcoal.ignoresSafeArea()

            PlayerLayerView(player: player, gravity: .resizeAspect)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // Hold to fast-preview at 2×; a swipe moves past `maximumDistance` and cancels the hold,
                // leaving the sheet's interactive dismiss untouched.
                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 12, pressing: { down in
                    fastForward = down
                    player.rate = down ? 2.0 : (scrubbing ? 0 : 1.0)
                    if down { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                }, perform: {})

            if fastForward {
                Text("2×")
                    .font(VeFont.sans(13, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.top, 16).padding(.leading, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 14) {
                Spacer()
                if !caption.isEmpty {
                    Text(caption)
                        .font(VeFont.serif(16, italic: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.4), in: Capsule())
                }
                scrubBar
                    .padding(.horizontal, 22)
                    .padding(.bottom, 34)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.top, 16).padding(.trailing, 16)
        }
        .animation(.easeOut(duration: 0.15), value: fastForward)
        .onAppear(perform: start_)
        .onDisappear {
            if let observer { player.removeTimeObserver(observer) }
            player.pause()
        }
    }

    /// A dedicated bottom scrub track — its own sub-view so its horizontal drag never fights the sheet's
    /// vertical swipe-down. Tap or drag anywhere on it to seek; the knob swells while scrubbing.
    private var scrubBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                Capsule().fill(.white).frame(width: f * w, height: 4)
                Circle().fill(.white)
                    .frame(width: scrubbing ? 18 : 13, height: scrubbing ? 18 : 13)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: f * w - (scrubbing ? 9 : 6.5))
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !scrubbing { scrubbing = true; player.pause() }
                        let frac = max(0, min(1, v.location.x / max(1, w)))
                        progress = frac
                        seek(toFraction: frac)
                    }
                    .onEnded { _ in
                        scrubbing = false
                        player.rate = fastForward ? 2.0 : 1.0   // resume (2× if still held)
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: scrubbing)
        }
        .frame(height: 44)
    }

    private func seek(toFraction f: Double) {
        let t = start + f * span
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func start_() {
        AudioSession.configureForPlayback()   // ensure sound plays even on silent mode
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        // Drive the scrub bar and loop the slice: when we pass the end, jump back to the start.
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.03, preferredTimescale: 600), queue: .main
        ) { time in
            guard !scrubbing else { return }   // don't fight the finger
            let t = time.seconds
            if t >= end - 0.02 {
                player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                progress = 0
                if !fastForward { player.play() }   // rate persists across the seek when held at 2×
            } else {
                progress = max(0, min(1, (t - start) / span))
            }
        }
    }
}
