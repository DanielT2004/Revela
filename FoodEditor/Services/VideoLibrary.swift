import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Video metadata

/// Lightweight stats about a video file, read with AVFoundation.
struct VideoMetadata: Equatable {
    let duration: Double      // seconds
    let width: Int            // display width (orientation-corrected)
    let height: Int           // display height (orientation-corrected)
    let fileSizeBytes: Int64

    var resolutionText: String { "\(width)×\(height)" }
    var durationText: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    /// TikTok wants vertical 9:16 — flag when the source isn't already portrait.
    var isPortrait: Bool { height >= width }
}

/// Reads metadata from a local video file using modern async AVFoundation loading.
enum VideoInspector {
    static func metadata(for url: URL) async -> VideoMetadata? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = CMTimeGetSeconds(try await asset.load(.duration))

            var w = 0, h = 0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let resolved = size.applying(transform)
                w = Int(abs(resolved.width).rounded())
                h = Int(abs(resolved.height).rounded())
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

            return VideoMetadata(duration: duration, width: w, height: h, fileSizeBytes: fileSize)
        } catch {
            Log.video("Failed to read metadata: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - PHPicker wrapper

/// One newly-picked clip, copied to a temp file we own, tagged with its photo-library identifier
/// (when known) so we can dedup against the existing selection.
struct PickedClip {
    let assetIdentifier: String?
    let url: URL
}

/// A SwiftUI wrapper around `PHPickerViewController` (videos only, **multi-select, ordered**). The
/// picker is **preselected** with the clips already in the session, so re-opening it ("Add more")
/// shows them as checked. Only genuinely-new selections are copied out and handed back — duplicates
/// are skipped. PHPicker needs no photo-library permission prompt.
struct VideoPicker: UIViewControllerRepresentable {
    /// Asset identifiers already in the session — shown as preselected so they aren't re-added.
    let preselectedIdentifiers: [String]
    /// PHPicker selection cap: `0` = unlimited multi-select (the editing flows); `1` = single video (the
    /// style-learning flows, which learn from one template video). Defaults to unlimited so existing call
    /// sites are unchanged.
    var selectionLimit: Int = 0
    /// Fired on the main queue the moment file copies begin, with an aggregate `Progress` covering them all —
    /// so a caller can dismiss the picker and show a determinate download overlay (iCloud-offloaded videos can
    /// take minutes to copy out). Optional; nil at call sites that don't surface progress.
    var onLoadingBegan: ((Progress) -> Void)? = nil
    /// Called with the newly-added clips (already deduped against the preselection), in pick order, plus how
    /// many eligible picks FAILED to load (e.g. an iCloud download that errored) so the caller can surface a
    /// toast instead of silently dropping them.
    let onPicked: ([PickedClip], _ failedCount: Int) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        // A photo-library-backed config is required for asset identifiers, ordered selection, and
        // preselection — none of which prompt for library access (the picker stays out-of-process).
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = selectionLimit   // 0 = unlimited multi-select; 1 = single video
        config.selection = .ordered          // results follow tap order; shows order numbers
        config.preferredAssetRepresentationMode = .current
        config.preselectedAssetIdentifiers = preselectedIdentifiers
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(_ parent: VideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Drop anything already in the session — only ingest new selections. (This also makes
            // Cancel a safe no-op, since a cancel returns the unchanged preselected set.)
            let preselected = Set(parent.preselectedIdentifiers)
            let newResults = results.filter { result in
                guard let id = result.assetIdentifier else { return true } // no id → treat as new
                return !preselected.contains(id)
            }
            Log.video("Picker closed: \(results.count) selected, \(newResults.count) new to ingest.")

            guard !newResults.isEmpty else {
                DispatchQueue.main.async { self.parent.onPicked([], 0) }
                return
            }

            let movieType = UTType.movie.identifier
            // Only movie-conforming picks actually load — count them so the aggregate progress and the
            // failed-count are measured against what we really attempt (not silently-skipped non-movies).
            let eligible = newResults.enumerated().filter {
                $0.element.itemProvider.hasItemConformingToTypeIdentifier(movieType)
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var byIndex: [Int: PickedClip] = [:]   // preserve pick order

            // One parent Progress covering every eligible copy — handed to the caller so it can show a
            // determinate download overlay (iCloud-offloaded clips can take minutes). Fired on main BEFORE any
            // completion can run so the began→picked ordering is guaranteed (main-queue FIFO).
            let parentProgress = Progress(totalUnitCount: Int64(max(eligible.count, 1)))
            if !eligible.isEmpty {
                let cb = self.parent.onLoadingBegan
                DispatchQueue.main.async { cb?(parentProgress) }
            }

            for (index, result) in eligible {
                let provider = result.itemProvider
                let assetID = result.assetIdentifier
                group.enter()
                let childProgress = provider.loadFileRepresentation(forTypeIdentifier: movieType) { url, error in
                    defer { group.leave() }
                    if let error {
                        Log.video("Item \(index) load error: \(error.localizedDescription)")
                        return
                    }
                    guard let url else {
                        Log.video("Item \(index) returned no URL.")
                        return
                    }
                    // The provided URL is deleted once this closure returns — copy it first.
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent("vela-source-\(UUID().uuidString)")
                        .appendingPathExtension(ext)
                    do {
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.copyItem(at: url, to: dest)
                        lock.lock(); byIndex[index] = PickedClip(assetIdentifier: assetID, url: dest); lock.unlock()
                        Log.video("Copied new item \(index) → \(dest.lastPathComponent)")
                    } catch {
                        Log.video("Item \(index) copy failed: \(error.localizedDescription)")
                    }
                }
                parentProgress.addChild(childProgress, withPendingUnitCount: 1)   // drives the download overlay
            }

            let attempted = eligible.count
            group.notify(queue: .main) {
                let ordered = eligible.map(\.offset).compactMap { byIndex[$0] }
                let failed = attempted - ordered.count
                Log.video("Handing back \(ordered.count) new clip(s)\(failed > 0 ? ", \(failed) failed to load" : "").")
                self.parent.onPicked(ordered, failed)
            }
        }
    }
}
