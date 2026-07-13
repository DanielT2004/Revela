import SwiftUI

/// A dimmed, determinate-progress overlay shown while the system copies a picked video out of the photo
/// library — most visibly when the clip is iCloud-offloaded ("Optimize iPhone Storage") and has to download
/// first. Without it the picker sheet dismisses to a screen that looks unchanged for minutes; this makes the
/// download visible so the pick never feels like a silent no-op. `ProgressView(_:)` observes the `Progress`
/// (fed by `VideoPicker.onLoadingBegan`) natively, so it fills as the copy advances.
struct MediaDownloadOverlay: View {
    let progress: Progress

    var body: some View {
        ZStack {
            Color.veCharcoal.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(progress)
                    .progressViewStyle(.linear).frame(width: 180).tint(Color.veTerracotta)
                Text("Getting your video from iCloud…")
                    .font(VeFont.sans(13, weight: .semibold)).foregroundStyle(Color.veCharcoal)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .transition(.opacity)
    }
}
