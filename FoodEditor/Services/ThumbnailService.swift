import AVFoundation
import UIKit

/// Generates still frames from a video for thumbnails (clip rows in M1, segment cards in M5).
enum ThumbnailService {
    /// In-memory cache so repeated / cross-screen requests (the reveal teaser vs. the full Retention Map,
    /// or returning to a screen) don't re-decode. Keyed by url + a coarse ~0.5s time bucket (matching the
    /// generator's own `requestedTimeToleranceAfter`, so nearby sample times share a frame) + max size.
    /// `NSCache` is thread-safe, so no actor is needed.
    private static let cache = NSCache<NSString, UIImage>()

    private static func cacheKey(_ url: URL, _ seconds: Double, _ maxSize: CGFloat) -> NSString {
        "\(url.absoluteString)@\(Int((max(0, seconds) * 2).rounded()))#\(Int(maxSize))" as NSString
    }

    /// A thumbnail from `seconds` into the clip (default: the very start). Cached in memory.
    static func thumbnail(for url: URL, at seconds: Double = 0.1, maxSize: CGFloat = 400) async -> UIImage? {
        let key = cacheKey(url, seconds, maxSize)
        if let hit = cache.object(forKey: key) { return hit }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true   // respect orientation
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        do {
            let result = try await generator.image(at: time)
            let img = UIImage(cgImage: result.image)
            cache.setObject(img, forKey: key)
            return img
        } catch {
            Log.video("Thumbnail failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Warm the cache for several times off one URL, bounded to a few concurrent generators so a burst
    /// can't spike CPU/memory or drop frames. Fire-and-forget from a view's `.task`.
    static func warm(url: URL, times: [Double], maxSize: CGFloat = 400) async {
        let pending = times.filter { cache.object(forKey: cacheKey(url, $0, maxSize)) == nil }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            let limit = 3
            var i = 0
            func submit(_ t: Double) { group.addTask { _ = await thumbnail(for: url, at: t, maxSize: maxSize) } }
            while i < min(limit, pending.count) { submit(pending[i]); i += 1 }
            while i < pending.count {
                await group.next()
                submit(pending[i]); i += 1
            }
        }
    }
}
