import SwiftUI
import UIKit

/// Create flow — step 7. "What should I learn from?" Upload new videos (wired) or use footage Vela has
/// (coming soon). Direct TikTok/IG pulls are deferred (same as onboarding).
struct CreateSourceView: View {
    @Environment(AppRouter.self) private var router
    @Environment(CreateFlow.self) private var create

    @State private var showPicker = false
    @State private var showSoon = false
    @State private var downloadProgress: Progress?     // non-nil while a picked video copies out of the library
    @State private var showLoadFailToast = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                BackChevronButton { router.back() }

                Text("NEW TEMPLATE")
                    .font(VeFont.sans(11, weight: .bold)).tracking(1.4).foregroundStyle(Color.veTerracotta)
                    .padding(.top, 22)
                Text("What should I\nlearn from?")
                    .font(VeFont.serif(30)).foregroundStyle(Color.veCharcoal).lineSpacing(2)
                    .padding(.top, 6)
                Text("Give Vela a video in the style you want. It'll learn it, then you review & save.")
                    .font(VeFont.sans(14.5)).foregroundStyle(Color.veNoteText).lineSpacing(3)
                    .padding(.top, 9)

                VStack(spacing: 13) {
                    optionRow(icon: "square.and.arrow.up", title: "Upload a new video",
                              subtitle: "Pick a video you've made from your camera roll", soon: false) {
                        create.startUpload()
                        showPicker = true
                    }
                    optionRow(icon: "rectangle.stack", title: "Use footage Vela has",
                              subtitle: "Choose from clips you've already imported", soon: true) {
                        showSoon = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
                .padding(.top, 24)

                Spacer(minLength: 16)

                ReasonNote(text: "Direct TikTok & Instagram pulls for new templates are coming — for now, submit the videos yourself.")
            }
            .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if showSoon {
                ToastView(text: "Using existing footage is coming soon")
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { showSoon = false }
                    }
            }
            if showLoadFailToast {
                ToastView(text: "Couldn't load that video — check your connection and try again.")
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { showLoadFailToast = false }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSoon)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showLoadFailToast)
        .background(Color.veCream.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPicker) {
            // Up to 3 finished videos per template — cross-video repetition is what turns a guess into a
            // confirmed signature (consolidation counts evidence per line/habit/beat). Onboarding stays 1.
            VideoPicker(preselectedIdentifiers: [], selectionLimit: 3,
                        onLoadingBegan: { progress in
                            showPicker = false           // dismiss the sheet; the overlay shows the copy
                            downloadProgress = progress
                        }) { picked, failedCount in
                showPicker = false
                downloadProgress = nil
                guard !picked.isEmpty else {
                    if failedCount > 0 { withAnimation { showLoadFailToast = true } }
                    return
                }
                create.ingest(picked)
                router.go(.createSelect)
            }
            .ignoresSafeArea()
        }
        .overlay { if let p = downloadProgress { MediaDownloadOverlay(progress: p) } }
    }

    private func optionRow(icon: String, title: String, subtitle: String, soon: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(soon ? AnyShapeStyle(Color.veSurface)
                                   : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE8B65E), Color.veTerracotta],
                                                                  startPoint: .topLeading, endPoint: .bottomTrailing)))
                    Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(soon ? Color.veTerracotta : .white)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(title).font(VeFont.sans(16, weight: .bold)).foregroundStyle(Color.veCharcoal)
                        if soon {
                            Text("SOON").font(VeFont.sans(9, weight: .heavy)).tracking(0.5).foregroundStyle(Color.veWarmGray)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.veSurface, in: Capsule())
                        }
                    }
                    Text(subtitle).font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xCFC6B6))
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)
            .opacity(soon ? 0.75 : 1)
        }
        .buttonStyle(.plain)
    }
}
