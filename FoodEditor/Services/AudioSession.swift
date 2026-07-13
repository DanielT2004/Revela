import AVFoundation

/// Configures the app's audio session for video playback. Without this the default `.ambient`
/// category is silenced by the hardware ring/silent switch — so previews would play with no sound.
/// `.playback` plays audio regardless of the switch (standard for any video app).
enum AudioSession {
    static func configureForPlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            Log.app("Audio session → .playback (sound plays even on silent mode).")
        } catch {
            Log.app("Audio session config failed: \(error.localizedDescription)")
        }
    }

    /// Voiceover recording (`NarrationRecorder`): `.playAndRecord` so the muted preview keeps rolling
    /// while the mic captures; `.defaultToSpeaker` because playAndRecord otherwise routes output to the
    /// earpiece; `.allowBluetooth` so a connected headset mic can be used. Call `configureForPlayback()`
    /// again when the take ends.
    static func configureForRecording() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default,
                                                            options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            Log.app("Audio session → .playAndRecord (voiceover recording).")
        } catch {
            Log.app("Audio session record config failed: \(error.localizedDescription)")
        }
    }
}
