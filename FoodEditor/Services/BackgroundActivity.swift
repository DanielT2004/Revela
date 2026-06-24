import UIKit

/// Runs an async operation under a UIKit background-task assertion, so the work keeps executing for the
/// short window iOS grants after the app is backgrounded (typically ~30s). We use it to let the
/// on-device proxy **upload** finish if the creator taps away mid-upload. The long analysis itself now
/// runs on the **server** (see `GeminiService.startAnalysisJob` + the `gemini-proxy` job runner), so it
/// no longer needs the app awake — only the brief upload does.
@MainActor
enum BackgroundActivity {
    static func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
        let app = UIApplication.shared
        var id: UIBackgroundTaskIdentifier = .invalid
        id = app.beginBackgroundTask(withName: name) {
            // Expiration handler — iOS is reclaiming the time; release the assertion.
            if id != .invalid { app.endBackgroundTask(id); id = .invalid }
        }
        defer { if id != .invalid { app.endBackgroundTask(id); id = .invalid } }
        return try await body()
    }
}
