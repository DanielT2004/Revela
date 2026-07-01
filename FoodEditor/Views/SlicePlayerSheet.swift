import SwiftUI
import AVKit

/// Plays (and gently loops) a single [start, end] slice of the merged proxy. Presented as a `.sheet`
/// so the system gives interactive swipe-down-to-dismiss for free (per the full-screen-video rule).
/// Shared by the post-analysis recap (`FirstCutView`) and Triage (`TriageView`).
struct SlicePlayerSheet: View {
    let url: URL
    let start: Double
    let end: Double
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var observer: Any?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.veCharcoal.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea()

            VStack {
                Spacer()
                if !caption.isEmpty {
                    Text(caption)
                        .font(VeFont.serif(16, italic: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.4), in: Capsule())
                        .padding(.bottom, 40)
                }
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
        .onAppear(perform: start_)
        .onDisappear {
            if let observer { player?.removeTimeObserver(observer) }
            player?.pause()
        }
    }

    private func start_() {
        AudioSession.configureForPlayback()   // ensure sound plays even on silent mode
        let p = AVPlayer(url: url)
        let startTime = CMTime(seconds: max(0, start), preferredTimescale: 600)
        p.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        p.play()
        // Loop the slice: when we pass the end, jump back to the start.
        observer = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { time in
            if time.seconds >= end - 0.05 {
                p.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                p.play()
            }
        }
        player = p
    }
}
