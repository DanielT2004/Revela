import AVFoundation

/// The voiceover **ducking envelope**, shared by the live preview (`PolishComposition`) and the final
/// export (`EditPlanAssembler`) so what you hear is what you get. Original footage audio (base clips +
/// audible B-roll) dips to `level` only while a narration take is playing, with short linear ramps —
/// the duck-in pre-rolls so the bed is already down when the voice starts, and releases just after the
/// take ends. Nothing is written into clip volumes: the envelope is applied at mix time, so moving,
/// trimming, or deleting a take automatically re-scopes it. Narration tracks are never ducked.
enum AudioDucking {
    static let rampSeconds = 0.15

    /// Timeline intervals covered by audible narration, merged when two takes sit closer than both
    /// ramps + 50ms — so the bed doesn't flutter back up between back-to-back takes.
    static func duckIntervals(for pieces: [NarrationPiece]) -> [ClosedRange<Double>] {
        let spans = pieces
            .filter { $0.volume > 0.001 && $0.fileOut - $0.fileIn > 0.05 }
            .map { $0.startOnBase...($0.startOnBase + ($0.fileOut - $0.fileIn)) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for s in spans {
            if let last = merged.last, s.lowerBound - last.upperBound < rampSeconds * 2 + 0.05 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, s.upperBound)
            } else {
                merged.append(s)
            }
        }
        return merged
    }

    /// The duck multiplier at time `t`: 1 outside, `level` inside a take, linear on the ramp edges.
    /// Ramp-in spans `[start − ramp, start]` (pre-roll), ramp-out spans `[end, end + ramp]`. Merged
    /// intervals are guaranteed ≥ 2 ramps apart, so edge zones never overlap.
    private static func duckFactor(at t: Double, duck: [ClosedRange<Double>], level: Float) -> Float {
        for d in duck {
            let rampInStart = d.lowerBound - rampSeconds
            let rampOutEnd = d.upperBound + rampSeconds
            guard t >= rampInStart, t <= rampOutEnd else { continue }
            if t >= d.lowerBound && t <= d.upperBound { return level }
            if t < d.lowerBound {
                let f = Float((t - rampInStart) / rampSeconds)          // 0…1 into the duck
                return 1 + f * (level - 1)
            }
            let f = Float((t - d.upperBound) / rampSeconds)             // 0…1 out of the duck
            return level + f * (1 - level)
        }
        return 1
    }

    /// Emit the volume events for ONE footage-audio track: per-piece volumes crossed with the duck
    /// envelope. Walks the union of piece-start and ramp-edge breakpoints in order; a segment whose
    /// volume changes across it (a ramp zone) becomes one `setVolumeRamp`, everything else a
    /// `setVolume` — events stay sorted and non-overlapping, as AVFoundation requires.
    /// `active: false` hard-mutes the whole track from t=0 (the preview's inactive base track, or the
    /// `originalAudioMuted` track flag — one code path for both).
    static func apply(to params: AVMutableAudioMixInputParameters,
                      pieces: [AudioPiece],
                      duck: [ClosedRange<Double>],
                      level: Float,
                      active: Bool) {
        guard active else { params.setVolume(0, at: .zero); return }
        let sorted = pieces.sorted { $0.baseStart < $1.baseStart }
        guard !sorted.isEmpty else { return }
        let lv = max(0, min(1, level))

        func pieceVolume(at t: Double) -> Float {
            var v = sorted[0].volume
            for p in sorted where p.baseStart <= t + 0.0005 { v = p.volume }
            return v
        }
        func vol(at t: Double) -> Float {
            pieceVolume(at: t) * duckFactor(at: max(0, t), duck: duck, level: lv)
        }

        // Breakpoints: piece starts + all four ramp edges of every duck interval.
        var marks: Set<Double> = [0]
        for p in sorted where p.baseStart > 0 { marks.insert(p.baseStart) }
        for d in duck {
            for e in [d.lowerBound - rampSeconds, d.lowerBound, d.upperBound, d.upperBound + rampSeconds]
            where e > 0 { marks.insert(e) }
        }
        let times = marks.sorted()

        var prev: Float = -1
        for (i, t) in times.enumerated() {
            let isLast = i + 1 >= times.count
            let next = isLast ? t + 1 : times[i + 1]
            let segLen = next - t
            guard segLen > 0.002 else { continue }
            let startVol = vol(at: t + 0.0005)
            let endVol = vol(at: next - 0.0005)
            let at = CMTime(seconds: t, preferredTimescale: 600)
            if !isLast, abs(startVol - endVol) > 0.001 {
                // A ramp zone (duck edge) — glide across the segment. A piece boundary inside a ramp
                // just splits it into two shorter glides with the right endpoints.
                params.setVolumeRamp(fromStartVolume: prev < 0 ? startVol : prev, toEndVolume: endVol,
                                     timeRange: CMTimeRange(start: at,
                                                            duration: CMTime(seconds: segLen, preferredTimescale: 600)))
                prev = endVol
            } else if abs(startVol - prev) > 0.001 {
                params.setVolume(startVol, at: at)
                prev = startVol
            }
        }
    }
}
