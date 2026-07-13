import SwiftUI
import UIKit

/// **The Screening Room** — the style-learn loading screen: filmstrip rows of the creator's real frames
/// under a warm reading lens (`ScreeningRoomLoader`), stage-aware serif marginalia, and an honest leave
/// pill (ochre "Keep Vela open" while compressing → sage "Free to go" the moment every upload hands off
/// to the server, with a one-time toast + success haptic). Driven by a `StyleAnalysisCoordinator`.
/// Reused by onboarding (step 3), the create-new-template flow, and the refine flow — the public
/// signature and both narration statics are unchanged from the phyllotaxis version.
struct AnalyzingStepView: View {
    let coordinator: StyleAnalysisCoordinator
    let clips: [SourceClip]
    var kicker: String? = nil                 // small top eyebrow (e.g. "NEW TEMPLATE") — onboarding omits it
    var title: String? = nil                  // optional top title (create flow)
    var narration: [String] = AnalyzingStepView.onboardingNarration
    let onDone: (StyleTemplate) -> Void
    let onBack: () -> Void

    @State private var narrationIndex = 0
    @State private var celebratedLeave = false      // one-time flip guard (haptic + toast)
    @State private var showFreeToast = false
    @State private var pulse = false                // ochre dot pulse (ProcessingView's blinking-dot idiom)
    @State private var sheetFrames: [UIImage] = []  // M3: real frames from WITHIN each video (post-canLeave)
    @State private var lensPulse: Date? = nil       // M3: one-beat lens brighten per analyzed video
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

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
        // Narration only rotates while the tape is actually being WATCHED — prep and synthesis show
        // purposeful stage lines instead (see `currentLine`). The timer stays inert otherwise.
        .onReceive(timer) { _ in
            guard coordinator.phase == .running, coordinator.stage == .watching else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                narrationIndex = (narrationIndex + 1) % max(1, narration.count)
            }
        }
        // The flip: every upload has handed off to the server — the one-time feel-good moment. A remount
        // mid-run can't re-fire it (canLeave is already true, so no change is observed).
        .onChange(of: coordinator.canLeave) { _, free in
            guard free, !celebratedLeave else { return }
            celebratedLeave = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showFreeToast = true }
            UIAccessibility.post(notification: .announcement,
                                 argument: "Free to go. We'll notify you when your style is ready.")
        }
        .overlay(alignment: .bottom) {
            if showFreeToast {
                ToastView(text: NotificationService.shared.notificationsEnabled
                          ? "You're free to go — we'll ping you."
                          : "You're free to go — check back in a minute or two.")
                    .padding(.bottom, 104)             // clears the leave pill
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { showFreeToast = false }
                    }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
        }
        // M3 — richer contact sheet: frames from WITHIN each video, generated ONLY after every upload has
        // handed off (never competing with the compress exports for CPU), at utility priority, hard-capped
        // at ~18 frames. Failures skip silently; leaving the screen cancels; kill-resume (no clips) no-ops.
        .task(id: coordinator.canLeave) {
            guard coordinator.canLeave, sheetFrames.isEmpty, !clips.isEmpty else { return }
            await Task(priority: .utility) {
                var frames: [UIImage] = []
                let perClip = min(6, max(2, 18 / max(1, clips.count)))
                for clip in clips {
                    guard !Task.isCancelled else { return }
                    let dur = clip.metadata?.duration ?? 0
                    guard dur > 0.5 else { continue }             // metadata not loaded yet → skip silently
                    for i in 0..<perClip {
                        let t = dur * (Double(i) + 0.5) / Double(perClip)
                        if let img = await ThumbnailService.thumbnail(for: clip.url, at: t, maxSize: 300) {
                            frames.append(img)
                        }
                    }
                }
                if !frames.isEmpty {
                    let out = frames
                    await MainActor.run { sheetFrames = out }     // append-once — no visible churn
                }
            }.value
        }
        // M3 — the lens "settles" on each finished video: a light tap + a brief brighten right as the
        // "VIDEO n OF N" slate ticks. Skipped under Reduce Motion (the crossfaded tick communicates it).
        .onChange(of: coordinator.analyzedCount) { _, _ in
            guard coordinator.phase == .running else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if !reduceMotion { lensPulse = Date() }
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

            ScreeningRoomLoader(thumbnails: sheetThumbnails,
                                stage: coordinator.stage,
                                progress: coordinator.progress,
                                analyzedCount: coordinator.analyzedCount,
                                totalCount: max(coordinator.totalCount, clips.count),
                                paused: coordinator.phase != .running || scenePhase != .active,
                                pulseDate: lensPulse)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(.top, title == nil ? 8 : 14)
                .animation(.easeInOut(duration: 0.3), value: sheetThumbnails.count)  // late thumbs fade in

            Spacer(minLength: 16)

            statusBlock

            progressBar.padding(.top, 8)
            leavePill.padding(.top, 12)
        }
        .padding(.horizontal, 26)
        .padding(.top, 70)
        .padding(.bottom, 24)
        // A way out while it's still working (network stall, wrong video). Cancel keeps the server job alive,
        // so re-entering with the same video re-attaches instead of re-paying — see StyleAnalysisCoordinator.
        .overlay(alignment: .topLeading) {
            BackChevronButton { coordinator.cancel(); onBack() }
                .padding(.leading, 20)
                .padding(.top, 20)
        }
    }

    /// Fallback chain: mid-video frames (M3, post-handoff) → first-frame thumbnails → resumed poster
    /// (kill-recovery: the clips are gone but the tile thumbnail survived) → empty (warm gradient tiles).
    private var sheetThumbnails: [UIImage] {
        if !sheetFrames.isEmpty { return sheetFrames }
        let real = clips.compactMap(\.thumbnail)
        if !real.isEmpty { return real }
        if let poster = coordinator.posterImage { return [poster] }
        return []
    }

    // MARK: marginalia + status

    /// Stage-aware marginalia: prep + synthesis get purposeful lines; watching rotates the caller's
    /// narration array (onboarding vs new-template — the statics below, unchanged).
    private var currentLine: String {
        switch coordinator.stage {
        case .compressing:  return "Prepping your footage…"
        case .uploading:    return "Sending it to the screening room…"
        case .watching:     return narration.isEmpty ? "" : narration[narrationIndex % max(1, narration.count)]
        case .synthesizing: return coordinator.label + "…"   // per-flow: "Finding what repeats/held up", "Putting your style into words"
        }
    }

    /// Transition identity — the note rises+fades on rotation AND on stage flips.
    private var lineKey: String {
        coordinator.stage == .watching ? "w\(narrationIndex)" : String(describing: coordinator.stage)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VELA IS WATCHING")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.6)
                .foregroundStyle(Color.veTerracotta)

            Text(currentLine)
                .font(VeFont.serif(24, italic: true))
                .foregroundStyle(Color.veCharcoal)
                .lineSpacing(3)
                .rotationEffect(.degrees(reduceMotion ? 0 : -2))
                .id(lineKey)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)),
                                          removal: .opacity.combined(with: .offset(y: -6))))
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.45), value: lineKey)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coordinator.label). Video \(coordinator.analyzedCount) of \(max(coordinator.totalCount, clips.count)). \(Int(coordinator.progress * 100)) percent complete.")
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xE2DACB))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xE8B65E), Color.veTerracotta],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0.02, coordinator.progress))
                    .animation(.easeOut(duration: 0.35), value: coordinator.progress)
            }
        }
        .frame(height: 8)
    }

    // MARK: leave pill — the honest "can I close the app?" answer, always on screen

    private var leavePill: some View {
        let free = coordinator.canLeave
        let ochre = Color(hex: 0x9A7350)
        let tint: Color = free ? .veSage : ochre
        return HStack(spacing: 8) {
            if free {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Circle().fill(tint).frame(width: 7, height: 7)
                    .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.35))
            }
            Text(free ? (NotificationService.shared.notificationsEnabled
                            ? "Free to go — we'll ping you when it's ready"
                            : "Free to go — notifications are off, check back in a minute or two")
                      : "Keep Vela open — prepping your footage")
                .font(VeFont.sans(12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)   // SE widths wrap, never truncate
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1))
        )
        .animation(reduceMotion ? .easeInOut(duration: 0.3)
                                : .spring(response: 0.4, dampingFraction: 0.8), value: free)
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
            // Retry only does something when there's actually something to retry: clips still in memory, OR a
            // kept recovery record (a soft timeout) to re-poll. After a kill with a terminally-failed job both
            // are gone, so retry() would just re-fail with "No videos to learn from" — hide it and make Back
            // the one clear action instead.
            if retryWorks {
                HStack(spacing: 10) {
                    Button("← Back", action: onBack)
                        .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veWarmGray)
                    Button("Retry") { coordinator.retry(clips: clips) }
                        .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veTerracotta)
                }
                .padding(.bottom, 30)
            } else {
                Button("← Back") { coordinator.reset(); onBack() }
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veTerracotta)
                    .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Retry is meaningful only if we can actually relaunch or re-poll: clips are still in memory, or a
    /// recovery record survives (a soft timeout keeps one; terminal failures clear it).
    private var retryWorks: Bool { !clips.isEmpty || coordinator.hasPendingRecord }

    // MARK: narration sets

    static let onboardingNarration = [
        "Pulling your video in…",
        "I see — you cut right on the bite.",
        "Your voice is carrying every story.",
        "Captions in your own words. Noted.",
        "Putting your style into words…",
    ]
    static let newTemplateNarration = [
        "Watching this new video…",
        "The pacing here is different.",
        "Picking up a separate set of habits.",
        "Drafting it as a new template…",
    ]
}
