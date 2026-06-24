import SwiftUI

/// Create flow — step 8. A 3-col multi-select grid of the picked videos; the more consistent they are, the
/// sharper the template. Sticky "Analyze N videos" kicks off the style extraction.
struct CreateSelectView: View {
    @Environment(AppRouter.self) private var router
    @Environment(CreateFlow.self) private var create

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 9), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackChevronButton { router.back() }

            Text("Pick videos to learn from")
                .font(VeFont.serif(27)).foregroundStyle(Color.veCharcoal).lineSpacing(2)
                .padding(.top, 20)
            Text("The more consistent the style across them, the sharper the template.")
                .font(VeFont.sans(13.5)).foregroundStyle(Color.veNoteText).lineSpacing(2)
                .padding(.top, 8)

            ScrollView {
                LazyVGrid(columns: cols, spacing: 9) {
                    ForEach(create.clips) { clip in cell(clip) }
                }
                .padding(.top, 18).padding(.bottom, 12)
            }

            bottomBar
        }
        .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.veCream.ignoresSafeArea())
    }

    private func cell(_ clip: SourceClip) -> some View {
        let on = create.selectedIDs.contains(clip.id)
        return Button { create.toggle(clip.id) } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = clip.thumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        ZStack { FoodTile(tone: FoodTone.tone(for: clip.id.hashValue), cornerRadius: 11); ProgressView().tint(.white) }
                    }
                }
                .aspectRatio(9.0/13.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.veTerracotta, lineWidth: on ? 2.5 : 0))

                checkmark(on)
            }
        }
        .buttonStyle(.plain)
    }

    private func checkmark(_ on: Bool) -> some View {
        Group {
            if on {
                ZStack {
                    Circle().fill(Color.veTerracotta)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
            } else {
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                    .background(Circle().fill(.white.opacity(0.25)))
                    .frame(width: 21, height: 21)
            }
        }
        .padding(6)
    }

    private var bottomBar: some View {
        VStack(spacing: 11) {
            HStack {
                Text("\(create.selectedCount) selected")
                    .font(VeFont.sans(13.5, weight: .bold)).foregroundStyle(Color.veCharcoal)
                Spacer()
                Text("Camera roll").font(VeFont.sans(12.5)).foregroundStyle(Color.veWarmGray)
            }
            if create.selectedCount > 0 {
                PrimaryActionButton(title: "Analyze \(create.selectedCount) video\(create.selectedCount == 1 ? "" : "s")") {
                    router.go(.createAnalyzing)   // AnalyzingStepView.task starts the coordinator
                }
            } else {
                Text("Select at least one")
                    .font(VeFont.sans(16, weight: .bold)).foregroundStyle(Color.veFaintGray)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color(hex: 0xE2DACB), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.top, 8)
    }
}
