import Foundation

/// App feature flags backed by `UserDefaults` (mirrors `EvalArtifactStore.isEnabled`). The decomposed
/// **two-AI pipeline** (PERCEIVE → DECIDE → ADAPT) is the new editor; the **monolith** single call is the
/// instant revert. DEBUG-default ON so we dogfood it; ships OFF until we flip it.
enum FeatureFlags {
    private static let twoCallKey = "velaTwoCallPipeline"

    static var twoCallPipeline: Bool {
        get {
            if UserDefaults.standard.object(forKey: twoCallKey) == nil {
                #if DEBUG
                return true
                #else
                return false
                #endif
            }
            return UserDefaults.standard.bool(forKey: twoCallKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: twoCallKey) }
    }
}
