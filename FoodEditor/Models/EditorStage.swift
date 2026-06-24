import Foundation

/// The three working surfaces of the editor, switched via the `StageSwitcher`:
/// **Sort** (TriageView) → **Arrange** (TimelineView) → **Polish** (PolishView). All three read and
/// mutate the SAME `EditPlanStore` (`VideoSession.store`), so moving between them is a pure view swap —
/// the edit is always "one video," whatever stage you're on. See `EditorShellView`.
enum EditorStage: Int, CaseIterable, Equatable {
    case sort, arrange, polish

    var title: String {
        switch self {
        case .sort:    return "Sort"
        case .arrange: return "Arrange"
        case .polish:  return "Polish"
        }
    }

    var index: Int { rawValue }

    /// The next / previous stage (for the switcher's strip-swipe), or nil at the ends.
    var next: EditorStage? { EditorStage(rawValue: rawValue + 1) }
    var prev: EditorStage? { EditorStage(rawValue: rawValue - 1) }
}
