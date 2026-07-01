import Foundation
import AVFoundation
import Speech

/// On-device speech-to-text for the footage's audio, producing **word-level timestamps** that anchor
/// Gemini's segmentation to REAL time. This is the cure for the timeline hallucination the harness measured
/// — Gemini read a 131s video as 212s long, inventing the back half. With a transcript (plus the exact
/// duration bound in `TranscriptPromptBuilder`), the model has ground-truth time anchors it can't drift off.
///
/// To save wall-clock time it transcribes the **source clips** so it can run CONCURRENTLY with the video
/// compression (they don't depend on each other) — mapping each clip's word times onto the merged-proxy
/// timeline exactly like `VideoPreprocessor` lays the clips out. Apple-native (Speech), on-device when
/// supported. Best-effort: NEVER throws into the paid pipeline — any failure returns `[]` and analysis
/// continues with just the duration bound. Requires `NSSpeechRecognitionUsageDescription` in Info.plist.
enum TranscriptionService {
    struct Word: Equatable { let text: String; let start: Double; let duration: Double }

    /// Request Speech authorization (idempotent). Returns whether we may transcribe.
    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// Transcribe the source clips in merged-proxy time. Mirrors `VideoPreprocessor`: clips with no video
    /// track are skipped (and don't advance the cursor), and each kept clip's words are offset by its start
    /// on the merged timeline — so the timestamps match the proxy Gemini watches. Runs concurrently with
    /// compression at the call site.
    static func transcribeClips(_ clips: [SourceClip]) async -> [Word] {
        guard !clips.isEmpty, await authorize() else {
            Log.audio("Transcript skipped (no clips or Speech not authorized).")
            return []
        }
        if clips.count == 1 { return await recognize(url: clips[0].url) }   // no offset math for a single clip

        var all: [Word] = []
        var cursor = 0.0
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else { continue }  // merge skips these
            let dur = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let words = await recognize(url: clip.url)
            all.append(contentsOf: words.map { Word(text: $0.text, start: $0.start + cursor, duration: $0.duration) })
            cursor += dur
        }
        return all
    }

    /// Transcribe a single already-merged file (used on the resume path, where the proxy is what survives).
    static func transcribe(url: URL) async -> [Word] {
        guard await authorize() else { Log.audio("Speech not authorized — skipping transcript."); return [] }
        return await recognize(url: url)
    }

    // MARK: - recognition core (no authorization — callers authorize once)

    /// iOS 26's `SpeechAnalyzer` is built for LONG-FORM audio. The legacy `SFSpeechRecognizer` path below is
    /// a short-dictation engine that returns near-empty results on multi-minute clips (it gave 1 word on a
    /// 2-minute video). Try the analyzer first; fall back to the legacy recognizer on older OS / failure.
    private static func recognize(url: URL, locale: Locale = Locale(identifier: "en-US")) async -> [Word] {
        if #available(iOS 26.0, *) {
            if let words = await recognizeWithAnalyzer(url: url, locale: locale) { return words }
            Log.audio("SpeechAnalyzer unavailable/failed — trying the legacy recognizer.")
        }
        return await recognizeLegacy(url: url, locale: locale)
    }

    /// Long-form, on-device transcription via the iOS 26 Speech framework, with word-level audio time
    /// ranges. Returns nil (not []) on a hard failure so the caller can fall back to the legacy recognizer.
    @available(iOS 26.0, *)
    private static func recognizeWithAnalyzer(url: URL, locale: Locale) async -> [Word]? {
        do {
            let transcriber = SpeechTranscriber(locale: locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [],
                                                attributeOptions: [.audioTimeRange])
            // Ensure the on-device model for this locale is installed (first run downloads it).
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Log.audio("Installing on-device speech model for \(locale.identifier)…")
                try await installation.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // Collect finalized results concurrently while the file is analyzed.
            let collector = Task { () -> [Word] in
                var out: [Word] = []
                for try await result in transcriber.results {
                    let attr = result.text
                    for run in attr.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let text = String(attr[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            out.append(Word(text: text, start: range.start.seconds, duration: range.duration.seconds))
                        }
                    }
                }
                return out
            }

            let t0 = Date()
            // SpeechAnalyzer reads a real AUDIO file. `AVAudioFile` on a VIDEO .mp4 reads almost nothing
            // (we saw 3 words / 0.3s) — extract the audio track to a temp .m4a first, then analyze THAT.
            let audioURL = await extractAudio(from: url) ?? url
            defer { if audioURL != url { try? FileManager.default.removeItem(at: audioURL) } }
            let audioFile = try AVAudioFile(forReading: audioURL)
            Log.audio("Audio for transcription: \(String(format: "%.1f", Double(audioFile.length) / max(audioFile.fileFormat.sampleRate, 1)))s (\(audioFile.length) frames).")
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let words = try await collector.value
            Log.audio("SpeechAnalyzer transcript: \(words.count) words in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s.")
            return words
        } catch {
            Log.audio("SpeechAnalyzer error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Extract a clip's audio track to a temp `.m4a` so the transcriber reads a real audio file (not a
    /// video container). Returns nil on failure (caller falls back to the original URL).
    private static func extractAudio(from url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("vela-audio-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: out)
        export.outputURL = out
        export.outputFileType = .m4a
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        return export.status == .completed ? out : nil
    }

    private static func recognizeLegacy(url: URL, locale: Locale) async -> [Word] {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            Log.audio("Speech recognizer unavailable (\(locale.identifier)) — skipping transcript."); return []
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        Log.audio("Transcribing audio (on-device: \(request.requiresOnDeviceRecognition))…")
        let t0 = Date()
        return await withCheckedContinuation { (cont: CheckedContinuation<[Word], Never>) in
            let lock = NSLock()
            var doneFlag = false
            func finish(_ words: [Word]) {
                lock.lock(); defer { lock.unlock() }
                guard !doneFlag else { return }
                doneFlag = true
                cont.resume(returning: words)
            }
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    Log.audio("Transcription error: \(error.localizedDescription)")
                    finish([]); return
                }
                guard let result, result.isFinal else { return }   // shouldReportPartialResults=false → one final
                let words = result.bestTranscription.segments.map {
                    Word(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                }
                Log.audio("Transcript: \(words.count) words in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s.")
                finish(words)
            }
            // Safety timeout so a stuck recognizer can't hang the foreground pipeline.
            Task {
                try? await Task.sleep(nanoseconds: 180_000_000_000)   // 180s
                lock.lock(); let already = doneFlag; lock.unlock()
                if !already { task.cancel(); Log.audio("Transcription timed out — proceeding without it."); finish([]) }
            }
        }
    }
}
