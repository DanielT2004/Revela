import SwiftUI
import UIKit

/// Screen 6 — the style library. Each card is a learned style; tap one to open its editor, tap "Use →"
/// to make it active. Remove a template with the corner **×** or by swiping the card left to reveal a
/// **Delete** affordance — both route through the same "are you sure?" confirmation. A dashed row on top
/// starts a new template.
struct TemplateLibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TemplateService.self) private var templates

    @State private var pendingDelete: StyleTemplate?   // drives the "are you sure?" confirmation
    @State private var showDeletedToast = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Native List so swipe-to-delete coexists with vertical scrolling (a raw DragGesture inside a
            // ScrollView captured the scroll). The header + create row ride as one borderless row.
            List {
                VStack(alignment: .leading, spacing: 0) {
                    BackChevronButton { router.back() }

                    Text("Your templates")
                        .font(VeFont.serif(31)).foregroundStyle(Color.veCharcoal)
                        .padding(.top, 22)
                    Text("Each one is a style Vela learned from a different set of videos. Tap one to make it active.")
                        .font(VeFont.sans(14)).foregroundStyle(Color.veNoteText).lineSpacing(3)
                        .padding(.top, 8)

                    createRow.padding(.top, 20)
                }
                .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 10)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ForEach(templates.templates) { template in
                    TemplateRow(
                        template: template,
                        isActive: template.id == templates.activeId,
                        poster: templates.poster(for: template.id),
                        onTap: { openEditor(template) },
                        onSetActive: { setActive(template) },
                        onRequestDelete: { pendingDelete = template }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 6, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = template } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Color.veTerracotta)
                    }
                }

                Color.clear.frame(height: 40)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.veCream.ignoresSafeArea())
            .confirmationDialog(
                "Delete this template?",
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { template in
                Button("Delete", role: .destructive) { performDelete(template) }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { template in
                Text("“\(template.name)” will be permanently removed. This can’t be undone.")
            }

            if showDeletedToast {
                ToastView(text: "Template deleted")
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { showDeletedToast = false }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showDeletedToast)
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

    // MARK: actions

    private func openEditor(_ template: StyleTemplate) {
        templates.beginEditing(template)
        router.go(.templateEditor)
    }

    private func setActive(_ template: StyleTemplate) {
        guard template.id != templates.activeId else { return }
        templates.setActive(template.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func performDelete(_ template: StyleTemplate) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)  // destructive haptic
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            templates.delete(template.id)                                 // removes the folder on disk + heals active id
        }
        pendingDelete = nil
        withAnimation { showDeletedToast = true }
    }
}

/// One template card. Tap opens the editor; swipe left (native `.swipeActions` on the parent List) reveals
/// Delete, and a corner **×** removes it directly — both ask the parent to confirm. Mirrors Home's `ProjectRow`.
private struct TemplateRow: View {
    let template: StyleTemplate
    let isActive: Bool
    let poster: UIImage?
    let onTap: () -> Void
    let onSetActive: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        cardBody
    }

    // MARK: card (the tile body)

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 13) {
            thumbnail
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
        .overlay(alignment: .topTrailing) { badge }
        .overlay(alignment: .topLeading) { deleteXButton }
        .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { onTap() }
    }

    /// Small always-visible remove affordance in the top-leading corner. Frosted white circle so the ×
    /// stays legible over any thumbnail; routes through the same confirmation as the swipe.
    private var deleteXButton: some View {
        Button { onRequestDelete() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.veCharcoal)
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())
                .shadow(color: Color.veCharcoal.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(7)
        .accessibilityLabel("Delete template")
    }

    @ViewBuilder
    private var badge: some View {
        if isActive {
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("ACTIVE").font(VeFont.sans(10, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color.veSage, in: Capsule())
            .padding(12)
        } else {
            Button { onSetActive() } label: {
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
    private var thumbnail: some View {
        Group {
            if let poster {
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

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(VeFont.sans(11, weight: .bold)).foregroundStyle(Color.veTerracotta)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.veTerracotta.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
