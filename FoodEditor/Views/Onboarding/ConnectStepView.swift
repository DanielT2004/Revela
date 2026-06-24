import SwiftUI

/// Onboarding step 2 — "Connect". Camera-roll import only for now (TikTok/IG deferred — see the seam below).
/// Tapping the card opens the system picker; clips land in the shared `VideoSession`. The CTA enables once
/// at least one clip is chosen, then advances to Analyzing (step 3).
struct ConnectStepView: View {
    @Environment(VideoSession.self) private var session

    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var showPicker = false

    private var hasClips: Bool { !session.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackChevronButton(action: onBack)

            Text("Show me a few\nof your videos")
                .font(VeFont.serif(31))
                .foregroundStyle(Color.veCharcoal)
                .lineSpacing(2)
                .padding(.top, 24)

            Text("Vela studies how you actually cut — your hooks, your pacing, your voice. Nothing is posted or changed.")
                .font(VeFont.sans(14.5))
                .foregroundStyle(Color.veNoteText)
                .lineSpacing(3)
                .padding(.top, 9)

            SourceCard(
                icon: "photo.stack",
                title: "Import from camera roll",
                subtitle: hasClips
                    ? "\(session.count) video\(session.count == 1 ? "" : "s") selected · tap to change"
                    : "Pick the videos to learn from",
                selected: hasClips
            ) { showPicker = true }
            .padding(.top, 22)

            // TODO: TikTok / Instagram import — deferred. Add more `SourceCard`s here when wired.

            Spacer(minLength: 24)

            if hasClips {
                PrimaryActionButton(title: "Connect & import", action: onContinue)
            } else {
                // Disabled-looking CTA (greyed) until a source is chosen.
                Text("Choose your videos")
                    .font(VeFont.sans(16, weight: .bold))
                    .foregroundStyle(Color.veFaintGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: 0xE2DACB), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.veCream.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPicker) {
            VideoPicker(preselectedIdentifiers: session.selectedAssetIdentifiers) { picked in
                showPicker = false
                session.ingest(picked)
            }
            .ignoresSafeArea()
        }
    }
}

/// A selectable source row (mockup's connect cards). Reusable so TikTok/IG can be slotted in later.
private struct SourceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.veSurface)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.veTerracotta)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VeFont.sans(16, weight: .bold))
                        .foregroundStyle(Color.veCharcoal)
                    Text(subtitle)
                        .font(VeFont.sans(13))
                        .foregroundStyle(Color.veWarmGray)
                }
                Spacer(minLength: 0)

                if selected {
                    ZStack {
                        Circle().fill(Color.veTerracotta)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 24, height: 24)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.veTerracotta, lineWidth: selected ? 2 : 0)
            )
            .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}
