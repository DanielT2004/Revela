import AVFoundation

/// Decodes an arbitrary audio file (e.g. ElevenLabs' MP3) into a composition-safe LPCM `.caf` by pumping
/// `AVAudioPCMBuffer`s through `AVAudioFile`. **Preset-independent** — it avoids `AVAssetExportSession`,
/// which is fragile on bare MP3 elementary streams (it commonly fails `canExport`), and avoids inserting
/// a raw MP3 source track into an `AVMutableComposition` (which inserts silent / throws).
///
/// The output is **float32 LPCM at the source sample rate + channel count**, which inserts and plays
/// reliably in `AVMutableComposition`/`AVPlayer` and exports via `AVAssetExportSession`.
///
/// Correctness note: `AVAudioFile.write(from:)` does NOT convert sample formats — so we create the writer
/// with the reader's own `processingFormat.settings` (float32) and the write is a straight passthrough.
enum AudioConvert {
    enum ConvertError: LocalizedError {
        case openFailed(String), writerFailed(String), emptySource
        var errorDescription: String? {
            switch self {
            case .openFailed(let m):   return "Couldn't open the cleaned audio: \(m)"
            case .writerFailed(let m): return "Couldn't write the cleaned audio: \(m)"
            case .emptySource:         return "The cleaned audio file was empty."
            }
        }
    }

    /// Reads `src` and writes a float32 LPCM `.caf` in the temp dir. Returns the new URL.
    static func toLPCM(_ src: URL) throws -> URL {
        let reader: AVAudioFile
        do { reader = try AVAudioFile(forReading: src) }
        catch { throw ConvertError.openFailed(error.localizedDescription) }

        // processingFormat is non-interleaved float32 at the source rate/channels, whatever the on-disk format.
        let format = reader.processingFormat
        guard reader.length > 0 else { throw ConvertError.emptySource }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-voice-\(UUID().uuidString).caf")
        try? FileManager.default.removeItem(at: outURL)

        // Reuse the reader's format settings verbatim so write(from:) does NO conversion.
        let writer: AVAudioFile
        do {
            writer = try AVAudioFile(forWriting: outURL,
                                     settings: format.settings,
                                     commonFormat: .pcmFormatFloat32,
                                     interleaved: false)
        } catch { throw ConvertError.writerFailed(error.localizedDescription) }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw ConvertError.writerFailed("Couldn't allocate a read buffer.")
        }

        while reader.framePosition < reader.length {
            try reader.read(into: buffer)          // sets buffer.frameLength (partial last chunk OK)
            if buffer.frameLength == 0 { break }   // safety: nothing more to read
            try writer.write(from: buffer)         // honors frameLength; straight passthrough
        }
        return outURL
    }
}
