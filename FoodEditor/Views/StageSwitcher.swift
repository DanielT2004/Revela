import SwiftUI

/// The persistent stage switcher from the "Navigation Options" mockup — **Sort · Arrange · Polish**.
/// Tap a segment to jump, or **swipe horizontally across the strip** to step to the previous/next stage
/// (the swipe is scoped to this strip so it never fights the card / timeline / clip drags inside a stage).
/// The active stage is a raised white pill with a terracotta dot; stages already reached show a sage ✓;
/// stages not yet reached are muted. A real `View` struct (no `AnyView`) so SwiftUI diffs it cleanly.
struct StageSwitcher: View {
    let current: EditorStage
    let furthest: EditorStage
    /// Reports intent (a tapped segment, or a swipe's prev/next). The shell decides what to do — e.g. a
    /// Sort tap after sorting opens the resume sheet (M2). This view never mutates state itself.
    let onSelect: (EditorStage) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(EditorStage.allCases, id: \.self) { stage in
                segment(stage)
            }
        }
        .padding(4)
        .background(Color.veSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Strip-only swipe: only a deliberate horizontal drag (not a tap, not a vertical move) steps stages.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height),
                          abs(v.translation.width) > 40 else { return }
                    if v.translation.width < 0, let n = current.next { onSelect(n) }
                    else if v.translation.width > 0, let p = current.prev { onSelect(p) }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: current)
    }

    @ViewBuilder
    private func segment(_ stage: EditorStage) -> some View {
        let isActive = stage == current
        let isDone = !isActive && stage.index <= furthest.index   // reached earlier → completed ✓
        Button { onSelect(stage) } label: {
            HStack(spacing: 5) {
                if isActive {
                    Circle().fill(Color.veTerracotta).frame(width: 7, height: 7)
                } else if isDone {
                    ZStack {
                        Circle().fill(Color.veSage).frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                Text(stage.title)
                    .font(VeFont.sans(13, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? Color.veCharcoal
                                     : (isDone ? Color.veNoteText : Color.veFaintGray))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isActive ? Color.white : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: isActive ? Color.veCharcoal.opacity(0.1) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
