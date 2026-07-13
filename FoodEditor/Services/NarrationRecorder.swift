import AVFoundation
import Observation
import UIKit

/// Records a voiceover take with the mic while the Polish preview plays muted. Owned by `PolishView`
/// as `@State` — a recording must die with the page (unlike the ElevenLabs coordinator, there's no
/// value in it outliving the view). Flow: mic permission → `.playAndRecord` session → 3-2-1 countdown
/// (haptic tick per digit) → `AVAudioRecorder` (AAC .m4a, 44.1kHz mono — composition-safe, same
/// family as `VoiceIsolationCoordinator.extractAudioSlice`) → metered levels for the live waveform →
/// auto-stop at `maxDuration` (the next take / video end). Every terminal path restores the playback
/// session and reports one `Outcome`.
@MainActor
@Observable
final class NarrationRecorder {
    enum Phase: Equatable { case idle, countdown(Int), recording }

    /// How a take ended. `.saved` hands over the file + its true recorded duration.
    enum Outcome {
        case saved(url: URL, duration: Double)
        case tooShort            // under `minTakeSeconds` — file already deleted
        case cancelled           // stopped during the countdown (no file was written)
        case denied              // mic permission refused
        case failed(String)      // recorder couldn't start
    }

    private(set) var phase: Phase = .idle
    /// Rolling input-level window (0…1) for the live meter, newest last.
    private(set) var levels: [Float] = []
    private(set) var elapsed: Double = 0
    /// Sticky "permission refused" flag so the panel can show an Open-Settings hint.
    private(set) var micDenied = false

    var isBusy: Bool { phase != .idle }

    static let minTakeSeconds = 0.5
    private static let levelWindow = 60
    private static let countdownBeat: UInt64 = 800_000_000   // 0.8s per digit — snappy but readable

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var maxDuration: Double = .infinity
    private var onRecordingBegan: (() -> Void)?
    private var completion: ((Outcome) -> Void)?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    /// Kick off a take into `directory`. `onRecordingBegan` fires when capture actually starts (after
    /// the countdown) — the view mutes + plays the preview there. `completion` fires exactly once per
    /// `start`, on the main actor, after the audio session is back on `.playback`.
    func start(into directory: URL, maxDuration: Double,
               onRecordingBegan: @escaping () -> Void,
               completion: @escaping (Outcome) -> Void) {
        guard phase == .idle else { return }
        self.maxDuration = max(Self.minTakeSeconds, maxDuration)
        self.onRecordingBegan = onRecordingBegan
        self.completion = completion

        countdownTask = Task { [weak self] in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard let self, !Task.isCancelled else { return }
            guard granted else {
                self.micDenied = true
                Log.audio("🎤 Mic permission denied — narration recording unavailable.")
                self.settle(.denied)
                return
            }
            self.micDenied = false
            AudioSession.configureForRecording()
            for n in [3, 2, 1] {
                self.phase = .countdown(n)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: Self.countdownBeat)
                if Task.isCancelled { return }
            }
            self.beginRecording(into: directory)
        }
    }

    /// Re-read the system mic permission (e.g. after a round-trip to Settings) so the sticky
    /// "Open Settings" hint clears without needing another take attempt. `.undetermined` counts as
    /// not-denied — the next Record tap runs the normal permission request.
    func refreshMicPermission() {
        micDenied = AVAudioApplication.shared.recordPermission == .denied
    }

    /// Stop button / end-of-video / backgrounding / page teardown. Stop-and-KEEP while recording;
    /// a stop during the countdown just cancels. Safe to call repeatedly.
    func stop() {
        switch phase {
        case .idle:
            return
        case .countdown:
            countdownTask?.cancel(); countdownTask = nil
            settle(.cancelled)
        case .recording:
            finish()
        }
    }

    // MARK: - Recording internals

    private func beginRecording(into directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("take-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { throw NSError(domain: "NarrationRecorder", code: 1) }
            recorder = r
            levels = []; elapsed = 0
            phase = .recording
            installObservers()
            startMeterTimer()
            onRecordingBegan?()
            Log.audio("🎤 Recording narration → \(url.lastPathComponent) (max \(String(format: "%.1f", maxDuration))s).")
        } catch {
            Log.audio("⚠️ Narration recorder failed to start: \(error.localizedDescription)")
            settle(.failed(error.localizedDescription))
        }
    }

    private func finish() {
        guard phase == .recording, let r = recorder else { return }
        let duration = r.currentTime   // capture BEFORE stop() — it reads 0 afterwards
        let url = r.url
        r.stop()
        recorder = nil
        if duration < Self.minTakeSeconds {
            try? FileManager.default.removeItem(at: url)
            Log.audio("🎤 Take discarded — \(String(format: "%.2f", duration))s is under \(Self.minTakeSeconds)s.")
            settle(.tooShort)
        } else {
            Log.audio("🎤 Take saved: \(String(format: "%.2f", duration))s → \(url.lastPathComponent).")
            settle(.saved(url: url, duration: duration))
        }
    }

    /// Single terminal path: tear down timers/observers, restore the playback session, report once.
    private func settle(_ outcome: Outcome) {
        meterTimer?.invalidate(); meterTimer = nil
        countdownTask = nil
        removeObservers()
        phase = .idle
        AudioSession.configureForPlayback()
        let cb = completion
        completion = nil
        onRecordingBegan = nil
        cb?(outcome)
    }

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.meterTick() }
        }
    }

    private func meterTick() {
        guard phase == .recording, let r = recorder else { return }
        r.updateMeters()
        let level = pow(10, r.averagePower(forChannel: 0) / 20)   // dBFS → 0…1
        levels.append(level)
        if levels.count > Self.levelWindow { levels.removeFirst(levels.count - Self.levelWindow) }
        elapsed = r.currentTime
        if elapsed >= maxDuration { finish() }   // reached the next take / the video's end
    }

    // MARK: - Interruptions (call / Siri) + route loss (BT mic vanished) → stop-and-keep

    private func installObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in
                Log.audio("🎤 Audio session interrupted — stopping the take (kept).")
                self?.finish()
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in
                Log.audio("🎤 Input route lost — stopping the take (kept).")
                self?.finish()
            }
        }
    }

    private func removeObservers() {
        if let o = interruptionObserver { NotificationCenter.default.removeObserver(o); interruptionObserver = nil }
        if let o = routeObserver { NotificationCenter.default.removeObserver(o); routeObserver = nil }
    }
}
