import SwiftUI
import UIKit

/// Screen 6 — the style library. Each card is a learned style; tap one to make it active. A dashed row
/// starts a new template (create flow lands in M6).
struct TemplateLibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TemplateService.self) private var templates

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackChevronButton { router.back() }

                Text("Your templates")
                    .font(VeFont.serif(31)).foregroundStyle(Color.veCharcoal)
                    .padding(.top, 22)
                Text("Each one is a style Vela learned from a different set of videos. Tap one to make it active.")
                    .font(VeFont.sans(14)).foregroundStyle(Color.veNoteText).lineSpacing(3)
                    .padding(.top, 8)

                createRow.padding(.top, 20)

                VStack(spacing: 12) {
                    ForEach(templates.templates) { template in
                        card(template)
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 40)
        }
        .background(Color.veCream.ignoresSafeArea())
    }

    private var createRow: some View {
        Button { router.go(.createSource) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.veSurface)
                    Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.veTerracotta)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a new template")
                        .font(VeFont.sans(15.5, weight: .bold)).foregroundStyle(Color.veCharcoal)
                    Text("Submit a new set of videos — learn a different style")
                        .font(VeFont.sans(12.5)).foregroundStyle(Color.veWarmGray)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xC9A269).opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(hex: 0xC9A269), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
        .buttonStyle(.plain)
    }

    private func card(_ template: StyleTemplate) -> some View {
        let isActive = template.id == templates.activeId
        // Card body = tap to edit; the "Use →" pill is a SEPARATE button (no nested buttons → no gesture clash).
        return HStack(alignment: .top, spacing: 13) {
            thumbnail(template)
            VStack(alignment: .leading, spacing: 0) {
                Text(template.name)
                    .font(VeFont.sans(15.5, weight: .bold)).foregroundStyle(Color.veCharcoal).lineLimit(1)
                Text(template.summary)
                    .font(VeFont.sans(12.5)).foregroundStyle(Color.veWarmGray).lineSpacing(1)
                    .lineLimit(2).padding(.top, 3)
                HStack(spacing: 6) {
                    chip("\(template.cutLabel) cuts")
                    chip(template.lenLabel)
                    chip(template.hookLabel)
                }.padding(.top, 9)
                Text("from \(template.count) video\(template.count == 1 ? "" : "s")")
                    .font(VeFont.sans(11.5)).foregroundStyle(Color.veFaintGray).padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.veTerracotta, lineWidth: isActive ? 2 : 0))
        .overlay(alignment: .topTrailing) { badge(isActive, template) }
        .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { openEditor(template) }
    }

    @ViewBuilder
    private func badge(_ isActive: Bool, _ template: StyleTemplate) -> some View {
        if isActive {
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("ACTIVE").font(VeFont.sans(10, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color.veSage, in: Capsule())
            .padding(12)
        } else {
            Button { setActive(template) } label: {
                Text("Use →")
                    .font(VeFont.sans(11.5, weight: .bold)).foregroundStyle(Color.veTerracotta)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.veTerracotta.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    @ViewBuilder
    private func thumbnail(_ template: StyleTemplate) -> some View {
        Group {
            if let poster = templates.poster(for: template.id) {
                Image(uiImage: poster).resizable().scaledToFill()
            } else {
                miniGrid(template.tones)
            }
        }
        .frame(width: 62, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func miniGrid(_ tones: [Int]) -> some View {
        let t = tones.isEmpty ? [0, 1, 4, 5] : tones
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                FoodTone.tone(for: t[i % t.count]).gradient
            }
        }
        .frame(width: 62, height: 82)
    }

    private func openEditor(_ template: StyleTemplate) {
        templates.beginEditing(template)
        router.go(.templateEditor)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(VeFont.sans(11, weight: .bold)).foregroundStyle(Color.veTerracotta)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.veTerracotta.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func setActive(_ template: StyleTemplate) {
        guard template.id != templates.activeId else { return }
        templates.setActive(template.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
