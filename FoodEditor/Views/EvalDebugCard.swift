#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only "Eval lab" card shown on Home. Compiled out of release entirely. Lets you toggle per-run
/// capture ([EvalArtifactStore]), AirDrop the saved run bundles to a Mac for the off-device prompt lab,
/// and run the [EditPlanValidator] self-check (this project has no XCTest target, so this is the green
/// signal). Pairs with the avatar long-press reset already on Home.
struct EvalDebugCard: View {
    @State private var capture = EvalArtifactStore.isEnabled
    @State private var twoCall = FeatureFlags.twoCallPipeline
    @State private var share: ShareItem?
    @State private var selfCheckResult: String?
    @State private var runCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVAL LAB · DEBUG")
                .font(VeFont.mono(10.5, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Color.veWarmGray)

            Toggle(isOn: $capture) {
                Text("Capture eval runs")
                    .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCharcoal)
            }
            .tint(Color.veTerracotta)
            .onChange(of: capture) { _, on in EvalArtifactStore.isEnabled = on }

            Toggle(isOn: $twoCall) {
                Text("Two-AI pipeline (PERCEIVE → DECIDE)")
                    .font(VeFont.sans(14, weight: .semibold)).foregroundStyle(Color.veCharcoal)
            }
            .tint(Color.veSage)
            .onChange(of: twoCall) { _, on in FeatureFlags.twoCallPipeline = on }

            HStack(spacing: 10) {
                Button {
                    runCount = EvalArtifactStore.runCount
                    if let url = EvalArtifactStore.exportAllZip() { share = ShareItem(url: url) }
                } label: {
                    Label("Share runs (\(runCount))", systemImage: "square.and.arrow.up")
                        .font(VeFont.sans(13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent).tint(Color.veTerracotta)

                Button(role: .destructive) {
                    EvalArtifactStore.wipeAll()
                    runCount = 0
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(VeFont.sans(13, weight: .semibold))
                }
                .buttonStyle(.bordered).tint(Color.veTerracotta)

                Button {
                    selfCheckResult = EditPlanValidator.selfCheck() ? "✅ validator OK" : "❌ validator FAILED — see console"
                } label: {
                    Label("Self-check", systemImage: "checkmark.seal")
                        .font(VeFont.sans(13, weight: .semibold))
                }
                .buttonStyle(.bordered).tint(Color.veSage)
            }

            if let r = selfCheckResult {
                Text(r).font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.veNote, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.veCharcoal.opacity(0.08), lineWidth: 1))
        .sheet(item: $share) { item in ActivityView(items: [item.url]) }
        .onAppear { runCount = EvalArtifactStore.runCount }
    }
}

/// Identifiable URL wrapper so `.sheet(item:)` can present the share sheet for the runs zip.
private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

/// Minimal `UIActivityViewController` bridge — AirDrops the runs zip to the Mac.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
