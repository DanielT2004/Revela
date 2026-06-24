import SwiftUI
import UIKit

/// The "Back to sorting" resume sheet (frame 3 of the Navigation Options mockup). Shown when the user
/// taps **Sort** after they've already moved past it — instead of dropping them into a stale swipe deck.
/// Two choices: **Review what you cut** (open the Cut Tray) or **Re-sort everything** (start the deck
/// over). Re-sort is destructive (it discards all edits), so it routes through an in-sheet confirmation
/// "page" rather than acting immediately — keeping the warning in one cohesive flow (no sheet→alert race).
struct ResumeSortSheet: View {
    let onContinue: () -> Void
    let onResort: () -> Void
    let onCancel: () -> Void

    /// Second "page": the destructive re-sort confirmation.
    @State private var confirmingResort = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xD8D0C2)).frame(width: 40, height: 4)
                .padding(.top, 14).padding(.bottom, 18)
            if confirmingResort {
                warningPage
            } else {
                optionsPage
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
        .background(Color.veCream)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: confirmingResort)
    }

    // MARK: - Page 1 — the two options

    private var optionsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Back to sorting")
                .font(VeFont.serif(23)).foregroundStyle(Color.veCharcoal)
            Text("Sort is a third way to edit — pick up your current cut, or start the deck over.")
                .font(VeFont.sans(13)).foregroundStyle(Color.veWarmGray)
                .padding(.top, 4).padding(.bottom, 18)

            optionRow(icon: "rectangle.stack",
                      tint: Color.veTerracotta,
                      title: "Continue sorting",
                      subtitle: "Pick up your current cut — all your edits are kept",
                      emphasized: true) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onContinue()
            }
            .padding(.bottom, 10)

            optionRow(icon: "arrow.clockwise",
                      tint: Color.veSage,
                      title: "Re-sort everything",
                      subtitle: "Discard edits and run the deck from the top",
                      emphasized: false) {
                withAnimation { confirmingResort = true }
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .font(VeFont.sans(13.5, weight: .bold)).foregroundStyle(Color.veWarmGray)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Page 2 — destructive re-sort confirmation

    private var warningPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(Color.veTerracotta.opacity(0.12)).frame(width: 42, height: 42)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18)).foregroundStyle(Color.veTerracotta)
                }
                Text("Start the sort over?")
                    .font(VeFont.serif(22)).foregroundStyle(Color.veCharcoal)
            }
            Text("This deletes all your progress — your clip order, trims, B-roll, and cuts — and re-runs the deck from the first clip. This can’t be undone.")
                .font(VeFont.sans(13.5)).foregroundStyle(Color.veNoteText)
                .lineSpacing(2)
                .padding(.top, 14).padding(.bottom, 20)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                onResort()
            } label: {
                Text("Delete progress & re-sort")
                    .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veOnTerracotta)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.veTerracotta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { withAnimation { confirmingResort = false } } label: {
                Text("Keep my edits")
                    .font(VeFont.sans(13.5, weight: .bold)).foregroundStyle(Color.veWarmGray)
                    .frame(maxWidth: .infinity).padding(.top, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row

    private func optionRow(icon: String, tint: Color, title: String, subtitle: String,
                           emphasized: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(VeFont.sans(14.5, weight: .bold)).foregroundStyle(Color.veCharcoal)
                    Text(subtitle).font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC3BBAC))
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(emphasized ? Color.veTerracotta.opacity(0.4) : Color.veCharcoal.opacity(0.06),
                            lineWidth: 1.5)
            )
            .shadow(color: Color.veCharcoal.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
