import SwiftUI

/// The "Vela is watching" screen — a phyllotaxis collage of the imported clips flying in, a center counter
/// of videos analyzed, rotating italic-serif narration, and a progress bar. Driven by a
/// `StyleAnalysisCoordinator`. Reused by onboarding (step 3) and the create-new-template flow (step 9).
struct AnalyzingStepView: View {
    let coordinator: StyleAnalysisCoordinator
    let clips: [SourceClip]
    var kicker: String? = nil                 // small top eyebrow (e.g. "NEW TEMPLATE") — onboarding omits it
    var title: String? = nil                  // optional top title (create flow)
    var narration: [String] = AnalyzingStepView.onboardingNarration
    let onDone: (StyleTemplate) -> Void
    let onBack: () -> Void

    @State private var narrationIndex = 0
    private let timer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    private var tileCount: Int { max(9, min(15, clips.isEmpty ? 9 : clips.count * 3)) }
    private var revealed: Int { min(tileCount, max(0, Int((coordinator.progress * Double(tileCount)).rounded()))) }

    var body: some View {
        ZStack {
            Color.veCream.ignoresSafeArea()
            switch coordinator.phase {
            case .failed(let message): errorState(message)
            default:                   analyzingState
            }
        }
        .task {
            coordinator.start(clips: clips)
            // If a reused coordinator is already finished (same clips), there's no phase change to observe.
            if coordinator.phase == .done, let t = coordinator.template { onDone(t) }
        }
        .onChange(of: coordinator.phase) { _, newValue in
            if newValue == .done, let t = coordinator.template { onDone(t) }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.45)) {
                narrationIndex = (narrationIndex + 1) % max(1, narration.count)
            }
        }
    }

    // MARK: analyzing

    private var analyzingState: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kicker {
                Text(kicker)
                    .font(VeFont.sans(11, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Color.veTerracotta)
            }
            if let title {
                Text(title)
                    .font(VeFont.serif(28)).foregroundStyle(Color.veCharcoal)
                    .lineSpacing(2).padding(.top, 6)
            }

            collage
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(.top, title == nil ? 8 : 14)

            Spacer(minLength: 16)

            Text("VELA IS WATCHING")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.6)
                .foregroundStyle(Color.veTerracotta)

            Text(narration.isEmpty ? "" : narration[min(narrationIndex, narration.count - 1)])
                .font(VeFont.serif(24, italic: true))
                .foregroundStyle(Color.veCharcoal)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                .padding(.top, 8)

            progressBar.padding(.top, 8)
        }
        .padding(.horizontal, 26)
        .padding(.top, 70)
        .padding(.bottom, 30)
    }

    private var collage: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                ForEach(0..<tileCount, id: \.self) { i in
                    tile(i).position(position(i, center: center))
                }
                centerBubble.position(center)
            }
        }
    }

    private func tile(_ i: Int) -> some View {
        let on = i < revealed
        return Group {
            if let thumb = clips.isEmpty ? nil : clips[i % clips.count].thumbnail {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                FoodTile(tone: FoodTone.tone(for: i), cornerRadius: 12)
            }
        }
        .frame(width: 64, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.20), radius: 8, y: 5)
        .rotationEffect(.degrees(Double((i * 53) % 26 - 13)))
        .scaleEffect(on ? 1 : 0.6)
        .opacity(on ? 1 : 0)
        .animation(.spring(response: 0.55, dampingFraction: 0.7), value: on)
    }

    /// Golden-angle (≈137.5°) spiral so tiles fan out evenly.
    private func position(_ i: Int, center: CGPoint) -> CGPoint {
        let angle = Double(i) * 2.39996
        let radius = 12 + Double(i) * 12
        return CGPoint(x: center.x + cos(angle) * radius * 1.25,
                       y: center.y + sin(angle) * radius * 0.8)
    }

    private var centerBubble: some View {
        VStack(spacing: 1) {
            Text("\(coordinator.analyzedCount)")
                .font(VeFont.serif(26)).foregroundStyle(Color.veTerracotta)
                .monospacedDigit()
            Text("of \(max(coordinator.totalCount, clips.count))")
                .font(VeFont.sans(10)).foregroundStyle(Color.veWarmGray)
        }
        .frame(width: 84, height: 84)
        .background(Color.veCream.opacity(0.92), in: Circle())
        .shadow(color: Color.veCharcoal.opacity(0.18), radius: 8, y: 4)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xE2DACB))
                Capsule().fill(Color.veTerracotta)
                    .frame(width: geo.size.width * max(0.02, coordinator.progress))
                    .animation(.easeOut(duration: 0.35), value: coordinator.progress)
            }
        }
        .frame(height: 8)
    }

    // MARK: error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34)).foregroundStyle(Color.veTerracotta)
            Text("Couldn't read your style")
                .font(VeFont.serif(22)).foregroundStyle(Color.veCharcoal)
            Text(message)
                .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            HStack(spacing: 10) {
                Button("← Back", action: onBack)
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veWarmGray)
                Button("Retry") { coordinator.retry(clips: clips) }
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veTerracotta)
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: narration sets

    static let onboardingNarration = [
        "Pulling your videos in…",
        "I see — you cut right on the bite.",
        "Your voice is carrying every story.",
        "Captions in your own words. Noted.",
        "Putting your style into words…",
    ]
    static let newTemplateNarration = [
        "Watching this new set of videos…",
        "The pacing here is different.",
        "Picking up a separate set of habits.",
        "Drafting it as a new template…",
    ]
}
